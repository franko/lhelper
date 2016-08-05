import glob
import os
import subprocess

recipe_scripts = glob.glob(os.path.join('build-recipes', '*.sh'))
recipe_scripts.sort()

env = os.environ

CFLAGS_BASE='-O2 -fomit-frame-pointer'
CXXFLAGS_BASE = "-O2 -fomit-frame-pointer -ffast-math"
INSTALL_PREFIX = '/c/fra/local'

env['CC_BASE'] = 'gcc'
env['CFLAGS_BASE'] = CFLAGS_BASE
env['CFLAGS_AGG'] = CXXFLAGS_BASE + " -ffast-math"
env['CXX_BASE'] = 'gcc'
env['CXXFLAGS_BASE'] = CXXFLAGS_BASE
env['CXXFLAGS_AGG'] = CXXFLAGS_BASE + " -fno-exceptions -fno-rtti"
env['CXXFLAGS_FOX'] = CXXFLAGS_BASE + " -fstrict-aliasing -finline-functions -fexpensive-optimizations"
env['BUILD_DIR'] = os.getcwd()
env['INSTALL_PREFIX'] = INSTALL_PREFIX

print(os.getcwd())

subprocess.check_call(["mkdir", "-p", INSTALL_PREFIX + "/lib/pkgconfig"])
subprocess.check_call(["mkdir", "-p", INSTALL_PREFIX + "/include"])
subprocess.check_call(["mkdir", "-p", INSTALL_PREFIX + "/bin"])

for filename_script in recipe_scripts:
    script_name = os.path.basename(filename_script).replace('.sh', '')
    if os.path.isfile(script_name + '.build-complete'):
        print("skipping: " + script_name)
        continue
    else:
        print("building: " + script_name)
        env['SCRIPT_NAME'] = script_name
        subprocess.check_call(["bash", filename_script], env=env)
