#!/usr/bin/env python

from setuptools import setup, find_packages

name = 'porkbun-ddns'

setup(name=name,
      version='1.0',
      # Modules to import from other scripts:
      packages=find_packages(),
      # Executables
      scripts=[name + '.py'])
