import logging

def setup_logging():
    FORMAT = '[%(asctime)-15s] [%(name)s] %(message)s'
    logging.basicConfig(format=FORMAT, level = logging.DEBUG)
