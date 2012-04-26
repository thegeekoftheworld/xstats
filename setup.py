from setuptools import setup, find_packages

setup(
    name='xstats',
    version='0.1.0',
    author='Xeross',
    author_email='xeross@theelitist.net',
    description='',
    packages=find_packages(),
    install_requires=[],
    data_files=[],
    scripts=[
        'xstats/daemon/bin/xstats-reporter',
        'xstats/daemon/bin/xstats-server'
    ]
)
