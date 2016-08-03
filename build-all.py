import glob
import os
import subprocess

recipe_scripts = glob.glob(os.path.join('build-recipes', '*.sh'))
recipe_scripts.sort()

env = os.environ

CFLAGS_BASE='-O2 -fomit-frame-pointer'
CXXFLAGS_BASE = "-O2 -fomit-frame-pointer -ffast-math"

env['CFLAGS_GSL'] = CFLAGS_BASE
env['CFLAGS'] = CFLAGS_BASE + " -ffast-math"
env['CXXFLAGS'] = CXXFLAGS_BASE
env['CXXFLAGS_AGG'] = CXXFLAGS_BASE + " -fno-exceptions -fno-rtti"

for filename_script in recipe_scripts:
    subprocess.check_call(["bash", filename_script], env=env)
