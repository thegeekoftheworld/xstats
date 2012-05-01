import psutil
import json
import pprint
import os
import gevent

from bottle import run, route, get, template, static_file

@route('/')
def index():
    return serve_static("index.html")

@route('/static/<filepath:path>')
def serve_static(filepath):
    return static_file(filepath, root='static')

run(host = '127.0.0.1', port = 8082, reloader = True)
