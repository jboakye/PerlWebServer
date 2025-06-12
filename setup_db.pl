#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use Socket;
use POSIX ":sys_wait_h";
use POSIX qw(mkfifo);
use JSON;
use IO::Socket;
use IO::Socket::INET;
use File::Slurp;
use DBI;
use DBD::SQLite;
use Data::Dumper;

#no warnings qw( experimental::autoderef );
#no warnings 'experimental::smartmatch';

use DBD::SQLite::Constants ':dbd_sqlite_string_mode';
my $unicode_opt = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;
my $db_file = "/dev/shm/web_server_db";
system("rm -fr $db_file");
my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file;sqlite_string_mode=$unicode_opt", '', '' );
$dbh->do(<<'END_SQL');
CREATE TABLE query_string
(
run_id  varchar(50) NOT NULL PRIMARY KEY,
query_string text
)
END_SQL

$dbh->do(<<'END_SQL');
CREATE TABLE content
(
run_id  varchar(50) NOT NULL PRIMARY KEY,
content text
)
END_SQL
