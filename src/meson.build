lhelper_sources = [
    'process.c',
    'env.c',
    'main.c',
]

lhelper_include = include_directories('.')

executable('lhelper-lua',
    lhelper_sources,
    include_directories: [lhelper_include],
    dependencies: lhelper_deps,
    c_args: lhelper_cargs,
    link_args: lhelper_linkargs,
    install: true,
)
