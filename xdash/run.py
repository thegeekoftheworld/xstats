from bottle import run, route, static_file

@route('/')
def index():
    return serve_static("index.html")

@route('/<filepath:path>')
def serve_static(filepath):
    return static_file(filepath, root='static')

run(host = '0.0.0.0', port = 8082, reloader = True)
