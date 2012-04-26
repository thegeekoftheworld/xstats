from gevent import monkey; monkey.patch_socket()

import functools

import ujson
import gevent
import redis

import network

from bottle import run, get, Bottle
from bottle.ext.websocket import GeventWebSocketServer, websocket

from redis.exceptions import ConnectionError as RedisConnectionError

from twiggy import log; logger = log.name(__name__)

class Session(network.ServerSession):
    def __init__(self, server, socket, address, publisher):
        # Stitch the publisher's `parse` method to this as the packet handler
        self.packetHandler = publisher.parse

        network.ServerSession.__init__(self, server, socket, address)


class Server(network.Server):
    def __init__(self, port, publisher):
        """
        :publisher: Publisher to push data to

        for more info see `xstats.daemon.network.Server`
        """

        # Use our custom `Session` object as session factory,
        # pass in `publisher` as default argument
        self.session = functools.partial(Session, publisher = publisher)

        network.Server.__init__(self, port)

class Module(object):
    """Base for publisher modules"""

    def push(self, data):
        """
        Called to push new data

        :data: Contains the packet data
        """
        pass

class WebsocketModule(Module):
    def __init__(self, host = '127.0.0.1', port = 8080):
        """
        Initialize websocket module

        :host: Host(IP) to listen on
        :port: Port to listen on
        """

        self.host = host
        self.port = port

        self.clients = set()
        self.app     = Bottle()

        self.log = logger.name("websocket") \
                         .fields(host = host, port = port)

        @self.app.get('/stats', apply=[websocket])
        def stats(ws):
            # Add the client
            self.clients.add(ws)

            # Start socket loop
            while True:
                msg = ws.receive()
                if msg is None:
                    break

            # Connection closed, remove client
            self.clients.remove(ws)

    def listen(self):
        """Spawn the bottle webserver in a greenlet"""
        gevent.spawn(self._start)

    def _start(self):
        """Run the websocket bottle app"""

        run(self.app, host = self.host,
                      port = self.port,
                      server = GeventWebSocketServer)
        self.log.debug("Started server at {}:{}", self.host, self.port)


    def push(self, packet):
        """Push data to all websocket clients that are connected"""

        self.log.debug("Pushing {}", packet)

        for client in self.clients:
            client.send(ujson.dumps(packet))

class RedisModule(Module):
    def __init__(self, host='127.0.0.1', port = 6379, db = 0):
        """
        Initialize the redis module

        :host: Host that redis is running on
        :port: Port to connect to
        :db:   Id of the DB to use
        """

        self.host = host
        self.port = port
        self.db   = db

        # Setup the redis API
        self.redis = redis.StrictRedis(host = host, port = port, db = db)

        self.disconnectedCache = {}

        self.log = logger.name("redis") \
                         .fields(host = host, port = port, db = db)

    def push(self, packet):
        """
        Push data to redis, if a connection can't be established store the data
        in the cache until we can successfully connect.

        :data: Data to push
        """

        keyName = "{}-{}".format(packet["host"], packet["module"])

        self.log.debug("Setting {}:{}", keyName, packet["data"])

        try:
            self.redis.hmset(keyName, packet["data"])
            self.flushCache()
        except RedisConnectionError:
            self.log.warning("Can't connect to Redis, caching '{}'", keyName)
            self.disconnectedCache[keyName] = packet["data"]

    def flushCache(self):
        if len(self.disconnectedCache) == 0:
            return

        self.log.info("Flushing cache...")

        pipeline = self.redis.pipeline()
        for key, data in self.disconnectedCache.iteritems():
            self.log.debug(" * Flushing {}", key)
            pipeline.hmset(key, data)

        self.disconnectedCache = {}

class Publisher(object):
    def __init__(self):
        self.modules = []

    def addModule(self, module):
        self.modules.append(module)

    def publish(self, data):
        for module in self.modules:
            module.push(data)

    def parse(self, packet):
        data = ujson.loads(packet)
        self.publish(data)

def start(port = 13337):
    """
    Starts the aggregator

    :port: Port to listen on for reporters
    """

    # Setup websocket module
    websocketModule = WebsocketModule()
    websocketModule.listen()

    # Setup redis module
    redisModule = RedisModule()

    # Setup publisher
    publisher = Publisher()
    publisher.addModule(websocketModule)
    publisher.addModule(redisModule)

    # Create server
    server = Server(13337, publisher)
    server.listen()

    # Wait for the server to finish up
    server.serverGreenlet.join()
