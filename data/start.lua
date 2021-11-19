EXEDIR = EXEFILE:match("^(.+)[/\\][^/\\]+$")
DATADIR = EXEDIR .. '/data'

package.path = DATADIR .. '/?.lua;' .. package.path
package.path = DATADIR .. '/?/init.lua;' .. package.path

