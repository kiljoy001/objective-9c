# Server and remote client test for o9 cross-machine dispatch
#
# Build and start the server:
#   cd /tmp/o9
#   6a o9_dispatch.s; 6c -FVw o9_runtime.c; 6c -FVw o9_dispatch.c
#   ar r libo9.a o9_runtime.6 o9_dispatch.6
#   cd o9c; rm -f y.tab.* o9c; yacc -d o9_plan9.y; 6c -o y.tab.6 y.tab.c; 6l -o o9c y.tab.6
#   ./o9c < test/counter_srv.o9 2> /tmp/o9/srv.c
#   cd /tmp/o9; 6c -FVw -o srv.6 srv.c; 6l -o counter_srv srv.6 libo9.a
#   rm /srv/Counter >[2]/dev/null; counter_srv &
#
# Build and run the client (in another window):
#   ./o9c < test/counter_client.o9 2> /tmp/o9/cli.c
#   cd /tmp/o9; 6c -FVw -o cli.6 cli.c; 6l -o counter_cli cli.6 libo9.a
#   counter_cli
