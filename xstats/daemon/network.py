import logging
import gevent

from gevent.server import StreamServer
from gevent.socket import create_connection
from gevent.queue import Queue

logger = logging.getLogger(__name__)

class Session(object):
    def __init__(self, socket = None, address = None):
        self.recvQueue = Queue()
        self.sendQueue = Queue()

        self.recvGreenlet = None
        self.sendGreenlet = None

        self.socket = socket
        self.address = address

    def log(self, string, level = 'debug'):
        string = "[%s:%s] %s" % (self.address[0], self.address[1], string)
        getattr(logger, level)(string)

    def _sendPacket(self, packet):
        self.socket.sendall(packet)
        self.log("Sent packet: {}".format(packet))

    def _sendLoop(self):
        while True:
            packet = self.sendQueue.get()
            self._sendPacket(packet)

    def send(self, packet):
        self.log("Sending packet: {}".format(packet))
        self.sendQueue.put("{}\n".format(packet))

    def _recvPacket(self, packet):
        self.log("Packet received: {}".format(packet))
        pass

    def _recvLoop(self):
        sockfile = self.socket.makefile()

        while True:
            packet = sockfile.readline()

            # Stop if packet is None
            if not packet:
                break

            self._recvPacket(packet)

        self.log("Socket disconnected")

    def start(self):
        self.log("Starting session loops")

        self.recvGreenlet = gevent.spawn(self._sendLoop)
        self.sendGreenlet = gevent.spawn(self._recvLoop)

class ServerSession(Session):
    def __init__(self, server, socket, address):
        self.server = server

        Session.__init__(socket, address)

    def _recvLoop(self):
        Session._recvLoop(self)
        self.server.handleDisconnect(self)

class Server(object):
    def __init__(self, port):
        self.port = port
        self.server = StreamServer(("0.0.0.0", port), self.handleConnect)
        self.serverGreenlet = None

        self.sessions = set()

    def listen(self):
        self.serverGreenlet = gevent.spawn(self.server.serve_forever)

    def handleConnect(self, socket, address):
        session = Session(socket, address)
        session.start()
        self.sessions.add(session)

    def handleDisconnect(self, session):
        self.sessions.remove(session)

    def sendAll(self, packet):
        for session in self.sessions:
            session.send(packet)

class Client(Session):
    def __init__(self, address):
        Session.__init__(self, address = address)

    def connect(self):
        self.socket = create_connection(self.address, 2)
        self.start()
