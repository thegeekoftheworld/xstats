from gevent import monkey; monkey.patch_socket()

import logging
import functools

import ujson
import gevent
import redis

import network

from bottle import run, get, Bottle
from bottle.ext.websocket import GeventWebSocketServer, websocket

logger = logging.getLogger(__name__)

class Session(network.ServerSession):
    def __init__(self, server, socket, address, publisher):
        self.packetHandler = publisher.parse

        network.ServerSession.__init__(self, server, socket, address)


class Server(network.Server):
    def __init__(self, port, publisher):
        self.session = functools.partial(Session, publisher = publisher)

        network.Server.__init__(self, port)

class Module(object):
    def push(self, data):
        pass

class WebsocketModule(Module):
    def __init__(self, host = '127.0.0.1', port = 8080):
        self.host = host
        self.port = port

        self.clients = set()
        self.app     = Bottle()

        @self.app.get('/stats', apply=[websocket])
        def stats(ws):
            self.clients.add(ws)

            while True:
                msg = ws.receive()
                if msg is None:
                    break

            self.clients.remove(ws)

    def listen(self):
        gevent.spawn(self._start)

    def _start(self):
        logger.debug(
            "Starting websocket server on {}:{}".format(self.host, self.port)
        )
        run(self.app, host = self.host,
                      port = self.port,
                      server = GeventWebSocketServer)


    def push(self, data):
        logger.debug("Pushing {}".format(data))

        for client in self.clients:
            client.send(ujson.dumps(data))

class RedisModule(Module):
    def __init__(self, host='127.0.0.1', port = 6379, db = 0):
        self.host = host
        self.port = port
        self.db   = db

    def connect(self):
        self.redis = redis.StrictRedis(host = self.host,
                                       port = self.port,
                                       db =   self.db)

    def push(self, data):
        logger.debug("Setting {}".format(data))

        redis_key = "{}-{}".format(data["host"], data["key"])
        self.redis.set(redis_key, data["value"])

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
    websocketModule = WebsocketModule()
    websocketModule.listen()

    redisModule = RedisModule()
    redisModule.connect()

    publisher = Publisher()
    publisher.addModule(websocketModule)
    publisher.addModule(redisModule)

    server = Server(13337, publisher)

    server.listen()
    logger.debug("Start listening...")

    # Wait for the server to finish up
    server.serverGreenlet.join()