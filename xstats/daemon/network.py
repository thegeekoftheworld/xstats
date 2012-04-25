import logging
import gevent

from gevent.event import Event
from gevent.server import StreamServer
from gevent.socket import create_connection
from gevent.queue import Queue
from gevent import socket

logger = logging.getLogger(__name__)

class DisconnectedException(Exception):
    pass

class Session(object):
    packetHandler = None

    def __init__(self, socket = None, address = None):
        self.sendQueue = Queue()

        self.recvGreenlet = None
        self.sendGreenlet = None
        self.finished = Event()

        self.cleanExit = False

        self.socket = socket
        self.address = address

    def log(self, string, level = 'debug'):
        string = "[%s:%s] %s" % (self.address[0], self.address[1], string)
        getattr(logger, level)(string)

    def _sendPacket(self, packet):
        self.log("Sending packet: {}".format(packet))
        self.socket.sendall("{}\n".format(packet))
        self.log("Sent packet: {}".format(packet))

    def _sendLoop(self):
        self.log("Starting send loop...")

        try:
            while True:
                packet = self.sendQueue.get()
                self._sendPacket(packet)
        except DisconnectedException:
            self.log("_sendLoop killed")
        finally:
            self.log("Send loop stopped")

    def send(self, packet):
        self.log("Queueing packet: {}".format(packet))
        self.sendQueue.put(packet)

    def _recvPacket(self, packet):
        packet = packet[:-1] # Remove trailing newline

        self.log("Packet received: {}".format(packet))

        if self.packetHandler:
            self.packetHandler(packet)

    def _recvLoop(self):
        self.log("Starting recv loop...")
        sockfile = self.socket.makefile()

        while True:
            packet = sockfile.readline()

            # Stop if packet is None
            if not packet:
                break

            self._recvPacket(packet)

        self.log("Socket disconnected")
        self.onDisconnect()
        self.log("Recv loop stopped")

    def start(self):
        self.log("Starting session loops")

        self.recvGreenlet = gevent.spawn(self._recvLoop)
        self.sendGreenlet = gevent.spawn(self._sendLoop)

    def disconnect(self):
        self.log("Disconnecting...")

        self.cleanExit = True
        self.socket.close()

        self.finished.set()

    def onDisconnect(self):
        self.sendGreenlet.kill(DisconnectedException)

        self.recvGreenlet = None
        self.sendGreenlet = None

class ServerSession(Session):
    def __init__(self, server, socket, address):
        self.server = server

        Session.__init__(self, socket, address)

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
    retryInterval = 5
    def __init__(self, address):
        Session.__init__(self, address = address)

    def connect(self):
        # Keep retrying the connection
        while True:
            try:
                self.socket = create_connection(self.address, 2)
                break
            except socket.error as e:
                self.log("Connect failed ({}), retrying in {} seconds".format(
                    e, self.retryInterval
                ))
                gevent.sleep(self.retryInterval)

        self.start()

    def _recvLoop(self):
        Session._recvLoop(self)
        self.connect()
