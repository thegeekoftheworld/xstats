from gevent import monkey; monkey.patch_time()

import functools
import socket
import time
import sys

from datetime import datetime

import ujson
import gevent

from network import Client

from xstats.net import stream_network_throughput_rolling_avg

from shared import parseConfig, loadModulesFromConfig, BasePublisher

from twiggy import log; logger = log.name(__name__)

def utc_unix_timestamp():
    """Return a unix timestamp based on UTC, in seconds"""
    return int(time.mktime(datetime.utcnow().timetuple()))

class Module(object):
    """Base for statistics gatherering modules"""

    # Name of the module
    name = "Undefined"

    def __init__(self):
        self.publisher = None
        self.greenlet  = None

    def start(self):
        """Start the gatherer"""

        self.greenlet = gevent.spawn(self.run)

    def run(self):
        """This will run in a separate greenlet"""
        pass

    def publishSingle(self, key, value):
        """
        Call the publisher with the data

        :key: Key of the statistic
        :value: Value of the statistic
        """

        self.publisher.publish(self.name, {key: value})

    def publishMulti(self, data):
        self.publisher.publish(self.name, data)

class BandwidthRollingAvgModule(Module):
    """Reports bandwidth rolling average."""

    name = "BwRollingAvg"

    def __init__(self, interface = None):
        """
        Initialize BandwidthRollingAvgModule

        :interface: Interface, combined if None, specific interface if string.
        """

        self.interface = interface

        Module.__init__(self)

    def run(self):
        stream_network_throughput_rolling_avg(callback = self.callback,
                                              interface = self.interface)

    def callback(self, average):
        interface = "all" if not self.interface else self.interface
        keyName   = "average-{}".format(interface)

        self.publishMulti({
            "{}-out".format(keyName): average[0],
            "{}-in".format(keyName): average[1],
        })

class Publisher(BasePublisher):
    def __init__(self, target):
        self.target = target

        BasePublisher.__init__(self)

    def addModule(self, module):
        module.publisher = self

        BasePublisher.addModule(self, module)

    def publish(self, moduleName, data):
        self.target(moduleName, data)

def send_publish_socket(moduleName, packetData, client, additional = {}):
    """
    Function that is used by the publisher to send its data.

    :packet_data: Data to send
    :value:       Value to send
    :client:      `Client` object to use to send the data
    :additional:  additional key/value pairs to send along
    """

    packet = {
        "module"   : moduleName,
        "data"     : packetData,
        "timestamp": utc_unix_timestamp()
    }

    packet.update(additional)
    client.send(ujson.dumps(packet))

def moduleFinder(name):
    moduleName = "{}Module".format(name)

    moduleClass = getattr(sys.modules[__name__], moduleName)
    return moduleClass

def start(args, hostname = socket.gethostname()):
    """
    Starts the reporter

    :address:  Aggregator to connect to
    :hostname: Hostname
    """

    # Modules will be completely overwritten but that's as intended
    defaults = {
        'host': '127.0.0.1',
        'port': 13337,
        'modules':{
            'Network': [
                {}
            ]
        }
    }

    # If no config file use dummy data
    if args.configFile:
        config = parseConfig(args.configFile, defaults = defaults)
    else:
        config = defaults

    if args.port:
        config["port"] = args.port
    if args.host:
        config["host"] = args.host

    # Initialize networking client
    client = Client((config["host"], config["port"]))

    # Create target function
    target = functools.partial(send_publish_socket, additional = {
        "host": hostname
    }, client = client)

    # Initialize the publisher
    publisher = Publisher(target)

    # Load modules
    loadModulesFromConfig(config, publisher, moduleFinder)

    # Start client and publisher
    client.connect()
    publisher.start()

    # Wait until client finishes
    try:
        client.finished.wait()
    except KeyboardInterrupt:
        client.disconnect()
        client.finished.wait()
