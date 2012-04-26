import gevent

from gevent.event import Event
from gevent.server import StreamServer
from gevent.socket import create_connection
from gevent.queue import Queue
from gevent import socket

from twiggy import log; logger = log.name(__name__)

class DisconnectedException(Exception):
    """
    Exception thrown when session gets disconnected, used to stop loops
    """

    pass

class Session(object):
    """
    Base class for network connections (sessions)
    """

    # Method to call when a packet arrives
    # if None don't call
    packetHandler = None

    def __init__(self, socket = None, address = None):
        """
        Initialize a `Session`

        :socket: Socket to use for this session
        :address: Address the socket is connected to/from
        """

        self.sendQueue = Queue()

        self.recvGreenlet = None
        self.sendGreenlet = None
        self.finished = Event()

        self.cleanExit = False

        self.socket = socket
        self.address = address

        self.log = logger.name("session") \
                         .fields(host = address[0], port = address[1])

    def _sendPacket(self, packet):
        """Send a packet, writing it to the socket"""

        try:
            self.log.debug("Sending packet: {}", packet)
            self.socket.sendall("{}\n".format(packet))
            self.log.debug("Sent packet: {}", packet)
        except socket.error as e:
            # If an error occurs put packet back on the queue
            self.log.error("Socket error: {}", e)
            self.disconnect()
            self.sendQueue.put(packet)

    def _sendLoop(self):
        """Loop for sending packets"""

        self.log.debug("Starting send loop...")

        try:
            while True:
                packet = self.sendQueue.get()
                self._sendPacket(packet)
        except DisconnectedException:
            self.log.debug("_sendLoop killed")
        finally:
            self.log.debug("Send loop stopped")

    def send(self, packet):
        """
        Send a packet.

        Queues the packet to be sent out as soon as possible.

        :packet: Packet to send
        """

        self.log.debug("Queueing packet: {}", packet)
        self.sendQueue.put(packet)

    def _recvPacket(self, packet):
        """
        Internal method for receiving a packet

        :packet: Packet received
        """
        packet = packet[:-1] # Remove trailing newline

        self.log.debug("Packet received: {}", packet)

        if self.packetHandler:
            self.packetHandler(packet)

    def _recvLoop(self):
        """Loop for receiving packets"""

        self.log.debug("Starting recv loop...")
        sockfile = self.socket.makefile()

        while True:
            packet = sockfile.readline()

            # Stop if packet is None
            if not packet:
                break

            self._recvPacket(packet)

        # Only error level if not clean exit
        if not self.cleanExit:
            self.log.error("Connection lost")
        else:
            self.log.debug("Socket disconnected")

        self.onDisconnect()
        self.log.debug("Recv loop stopped")

    def start(self):
        """Starts the recv and send loops"""

        self.log.debug("Starting session loops")

        self.recvGreenlet = gevent.spawn(self._recvLoop)
        self.sendGreenlet = gevent.spawn(self._sendLoop)

    def disconnect(self):
        """Cleanly disconnect the connection"""

        self.log.debug("Disconnecting...")

        self.cleanExit = True
        self.socket.close()

        self.finished.set()

    def onDisconnect(self):
        """Method called on disconnect"""

        self.sendGreenlet.kill(DisconnectedException)

        self.recvGreenlet = None
        self.sendGreenlet = None

class ServerSession(Session):
    """
    Server specific implementation of a `Session`
    """

    def __init__(self, server, socket, address):
        """
        Initialize `ServerSession`

        :server: Server this connection is spawned from

        For more info see `Session.__init__`
        """

        self.server = server

        Session.__init__(self, socket, address)

    def _recvLoop(self):
        """Modified `_recvLoop` to let the `Server` handle disconnects properly"""

        Session._recvLoop(self)
        self.server.handleDisconnect(self)

class Server(object):
    """
    Listens for incoming connections and keeps track of active sessions
    """

    # What to use as session factory
    session = ServerSession

    def __init__(self, port):
        """
        Initialize the `Server`

        :port: Port to listen on
        """

        self.port = port
        self.server = StreamServer(("0.0.0.0", port), self.handleConnect)
        self.serverGreenlet = None

        self.sessions = set()

        self.log = logger.name("server") \
                         .fields(port = port)

    def listen(self):
        """Start listening"""

        self.serverGreenlet = gevent.spawn(self.server.serve_forever)
        self.log.info("Started listening on port {}", self.port)

    def handleConnect(self, socket, address):
        """
        Handle a new connection

        :socket: Socket object for the connection
        :address: (ip, port) tuple of the remote client
        """

        self.log.info("Client connected from {}:{}", address[0], address[1])

        session = self.session(self, socket, address)
        session.start()

        # Add session to active sessions
        self.sessions.add(session)

    def handleDisconnect(self, session):
        """
        Handle a client disconnecting

        :session: Session of the client that disconnected
        """

        # Remove session from active sessions
        self.sessions.remove(session)

    def sendAll(self, packet):
        """
        Send a packet to all sessions

        :packet: Packet to send
        """

        for session in self.sessions:
            session.send(packet)

class Client(Session):
    """Client specific extension to `Session` including reconnect"""

    # How long to wait between reconnect intervals
    retryInterval = 5

    def __init__(self, address):
        """
        Initialize the client

        :address: (host, port) tuple to connect to
        """

        Session.__init__(self, address = address)

    def connect(self):
        """Connect to a server"""

        # Reset `cleanExit`
        self.cleanExit = False

        # Keep retrying the connection
        while True:
            try:
                self.socket = create_connection(self.address, 2)
                break
            except socket.error as e:
                self.log.debug("Connect failed ({}), retrying in {} seconds",
                    e, self.retryInterval
                )
                gevent.sleep(self.retryInterval)

        self.start()

    def _recvLoop(self):
        """Modified `_recvLoop` to implement automatic reconnecting"""

        Session._recvLoop(self)
        self.connect()
