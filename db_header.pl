use DBD::SQLite::Constants ':dbd_sqlite_string_mode';
my $unicode_opt = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;
my $db_file = "/dev/shm/web_server_db";
my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file;sqlite_string_mode=$unicode_opt", '', '' );
