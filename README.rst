xStats
=============

xStats is a server/client application that can be used to gather server
statistics and send them to a central location, and can then be stored or
otherwise used for whatever purpose you might have.

Currently 2 modules have been written for the aggregator (server), one that
exposes a websocket one can connect to to receive stats, and one that stores
them in redis.

Installation
------------

1. Create a virtualenv (optional)
2. Install requirements ``pip install -r requirements.txt``
3. Configure reporter/aggregator using example from ``config-example/``
4. Run using ``xstats-server -c <config>`` or ``xstats-reporter -c <config>``

xDash
=====
xDash is an example dashboard written using Coffeescript that showcases the use
of the websocket module, it's configurable for multiple servers
however optimal use would probably be between 4-8 servers.

Installation
------------

1. Make sure that the Websocket module is enabled on the aggregator
2. Copy the contents of ``xdash/static/`` to a folder accessible from the web
   or run ``xdash/run.py`` (requires Bottle) to make the files accessible
3. Copy ``config.js.example`` to ``config.js`` and configure it for your set-up
4. Browse to whatever URL the dashboard is accessible on and it should work.

Todo
====

* Daemonization
* Configurable logging
* Tweak logging output
