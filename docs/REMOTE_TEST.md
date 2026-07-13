# Server and remote client test for o9 cross-machine dispatch
#
# Build and start the server:
#   cd /tmp/o9
#   mk
#   o9c/o9c < o9c/test/counter_srv.o9 > srv.c
#   6c -FVw -I. -o srv.6 srv.c
#   6l -o counter_srv srv.6 libo9.a /$objtype/lib/libndb.a
#   rm /srv/Counter >[2]/dev/null; counter_srv &
#
# Build and run the client (in another window):
#   o9c/o9c < o9c/test/counter_client.o9 > cli.c
#   6c -FVw -I. -o cli.6 cli.c
#   6l -o counter_cli cli.6 libo9.a /$objtype/lib/libndb.a
#   counter_cli
