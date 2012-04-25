import psutil
import json
import pprint
import os
import gevent

from bottle import run, route, get, template, static_file
from bottle.ext.websocket import GeventWebSocketServer, websocket

interval = 0.2          # Refresh send interval (In seconds)

previous_stats = None
clients = set()         # Set of connected websocket clients

def get_stats():
    global previous_stats

    # Assuemble statistics
    stats = {
        'cpu': {
            'pct': psutil.cpu_percent(percpu = True),
            'avg': os.getloadavg(),
        },
        'mem': psutil.phymem_usage()._asdict(),
        'swp': psutil.virtmem_usage()._asdict(),
        'net': {iface: data._asdict() for iface, data in psutil.network_io_counters(True).iteritems()}
    }

    # Iterate over interfaces
    for iface, data in stats['net'].iteritems():

        # Set to zero if interface doesn't exist or previous_stats are zero
        if not previous_stats or not iface in previous_stats['net']:
            data['packets_recv_sec'] = 0
            data['packets_sent_sec'] = 0
            data['bytes_recv_sec'] = 0
            data['bytes_sent_sec'] = 0

            continue

        # Calculate packet/byte rate/s
        if previous_stats:

            # Alias for previous stats
            old_data = previous_stats['net'][iface]

            data['packets_recv_sec'] = (data['packets_recv'] - old_data['packets_recv']) / interval
            data['packets_sent_sec'] = (data['packets_sent'] - old_data['packets_sent']) / interval
            data['bytes_recv_sec']   = (data['bytes_recv']   - old_data['bytes_recv'])   / interval
            data['bytes_sent_sec']   = (data['bytes_sent']   - old_data['bytes_sent'])   / interval


    # Save previous state
    previous_stats = stats
    return stats

def stats_loop():
    """Update and send out the statistics."""

    while True:
        json_string = json.dumps(get_stats())
        for client in clients:
            client.send(json_string)

        gevent.sleep(interval)

@route('/')
def index():
    return template('tpl/layout.tpl')

@get('/stats', apply=[websocket])
def stats(ws):
    clients.add(ws)

    while True:
        msg = ws.receive()
        if msg is not None:
            continue
        else:
            break

    clients.remove(ws)

@route('/static/<filepath:path>')
def server_static(filepath):
    return static_file(filepath, root='static')


stats_greenlet = gevent.spawn(stats_loop)
run(host = '127.0.0.1', port = 8080, server = GeventWebSocketServer)
