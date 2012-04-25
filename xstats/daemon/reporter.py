from gevent import monkey; monkey.patch_time()

import functools
import socket

import ujson
import gevent

from network import Client

from xstats.net import stream_network_throughput_rolling_avg

class Module(object):
    def __init__(self, publisher):
        self.publisher = publisher
        self.greenlet = None

    def start(self):
        self.greenlet = gevent.spawn(self.run)

    def run(self):
        pass

    def publish(self, key, value):
        self.publisher.publish(key, value)

class NetworkModule(Module):
    def run(self):
        stream_network_throughput_rolling_avg(callback = self.callback)

    def callback(self, average):
        self.publish("network-average", average)

class Publisher(object):
    interval = 1

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
    packet = {
        key: value
    }

    packet.update(additional)

    client.send(ujson.dumps(packet))

def start(address, hostname = socket.gethostname()):
    client = Client(address)
    target = functools.partial(send_publish_socket, additional = {
        "host": hostname
    }, client = client)
    publisher = Publisher(target)

    publisher.loadModule(NetworkModule)

    client.connect()
    publisher.start()

    return client
