from functools import partial
from twiggy import quickSetup, levels

import yaml

def setup_logging(level = 'DEBUG', file = None):
    """
    Initialize the logging

    TODO: More advanced configuration for logging, based on config?
    """

    quickSetup(min_level = getattr(levels, level), file = file)

def parseConfig(filename, defaults = None):
    """
    Parse a config file, including support for defaults

    :filename: File to parse
    :defaults: Default values
    """

    # Copy defaults as base for result
    result = defaults.copy() if defaults else {}

    # Load and parse the config file
    configText = open(filename).read()
    config = yaml.load(configText, Loader = yaml.CLoader)

    # Update result with config
    result.update(config)

    return result

def loadModulesFromConfig(config, host, finder):
    """
    Load modules based on the `config` dictionary, instantiating them and
    calling the `addModule` method of `host` to register them.

    Uses the `finder` callable to get a valid Class back.
    """

    # Loop through all modules
    for moduleName, moduleConfigs in config["modules"].iteritems():

        # Find module using moduleFinder
        moduleClass = finder(moduleName)

        # Loop through all configs per module
        for moduleConfig in moduleConfigs:

            # Instantiate and start module
            module = moduleClass(**moduleConfig)

            # Add to module host
            host.addModule(module)

class BasePublisher(object):
    def __init__(self):
        self.modules = []

    def start(self):
        for module in self.modules:
            module.start()

    def addModule(self, module):
        self.modules.append(module)
