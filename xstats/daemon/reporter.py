from gevent import monkey; monkey.patch_time()

import functools
import socket
import time
from datetime import datetime

import ujson
import gevent

from network import Client

from xstats.net import stream_network_throughput_rolling_avg

from twiggy import log; logger = log.name(__name__)

def utc_unix_timestamp():
    """Return a unix timestamp based on UTC, in seconds"""
    return int(time.mktime(datetime.utcnow().timetuple()))

class Module(object):
    """Base for statistics gatherering modules"""

    def __init__(self, publisher):
        """
        Initialize module

        :publisher: Publisher to use when publishing data
        """

        self.publisher = publisher
        self.greenlet = None

    def start(self):
        """Start the gatherer"""

        self.greenlet = gevent.spawn(self.run)

    def run(self):
        """This will run in a separate greenlet"""
        pass

    def publish(self, key, value):
        """
        Call the publisher with the data

        :key: Key of the statistic
        :value: Value of the statistic
        """

        self.publisher.publish(key, value)

class NetworkModule(Module):
    """Reports network statistics, bandwidth usage up/down, packet/s, etc."""

    def run(self):
        stream_network_throughput_rolling_avg(callback = self.callback)

    def callback(self, average):
        self.publish("network-average", average)

class Publisher(object):
    def __init__(self, target):
        self.target = target
        self.modules = []

    def loadModule(self, moduleClass):
        self.modules.append(moduleClass(self))

    def publish(self, key, value):
        self.target(key, value)

    def start(self):
        for module in self.modules:
            module.start()

def send_publish_socket(key, value, client, additional = {}):
    """
    Function that is used by the publisher to send its data.

    :key:        Key to send
    :value:      Value to send
    :client:     `Client` object to use to send the data
    :additional: additional key/value pairs to send along
    """
    packet = {
        "key"      : key,
        "value"    : value,
        "timestamp": utc_unix_timestamp()
    }

    packet.update(additional)
    client.send(ujson.dumps(packet))

def start(address, hostname = socket.gethostname()):
    """
    Starts the reporter

    :address:  Aggregator to connect to
    :hostname: Hostname
    """

    client = Client(address)

    # Create target function
    target = functools.partial(send_publish_socket, additional = {
        "host": hostname
    }, client = client)

    # Initialize the publisher
    publisher = Publisher(target)
    publisher.loadModule(NetworkModule)

    # Start client and publisher
    client.connect()
    publisher.start()

    # Wait until client finishes
    try:
        client.finished.wait()
    except KeyboardInterrupt:
        client.disconnect()
        client.finished.wait()
