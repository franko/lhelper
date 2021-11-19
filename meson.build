project('lhelper', 'c', version : '0.1', meson_version : '>= 0.54', default_options : ['c_std=gnu11'])

cc = meson.get_compiler('c')

lhelper_cargs = []
lhelper_linkargs = []

libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)
lua_dep = dependency('lua5.2', fallback: ['lua', 'lua_dep'],
    default_options: ['shared=false', 'use_readline=false', 'app=false']
)
reproc_dep = dependency('reproc', fallback: ['reproc', 'reproc_dep'],
    default_options: [
        'default_library=static', 'multithreaded=false', 'reproc-cpp=false', 'examples=false'
    ]
)
lhelper_deps = [lua_dep, reproc_dep, libm, libdl]

if host_machine.system() == 'windows'
    # Note that we need to explicitly add the windows socket DLL because
    # the pkg-config file from reproc does not include it.
    lhelper_deps += cc.find_library('ws2_32', required: true)
endif

subdir('src')

