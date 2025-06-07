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
use Data::Dumper;

#no warnings qw( experimental::autoderef );
#no warnings 'experimental::smartmatch';

my $CONFIG_FILE = "./config.conf.json";
my $logFile = "";
my $fifopath = "/tmp/IBWSFIFO";
$SIG{USR1} = \&sigRequestDone;
my $MAX_LISTEN = 5;
my $routes = [];
my $confs = {};
my @fils  = ();
my $requetesR = 0;
my $requetesT = 0;
my $mainPid;

checkParameter();

sub checkParameter
{
    die "Parameter : start/stop/status\n" if @ARGV != 1;

    if ($ARGV[0] eq "start")
    {
        start();
    }
    elsif ($ARGV[0] eq "stop")
    {
        stop();
    }
    elsif ($ARGV[0] eq "status")
    {
        status();
    }
    else
    {
        die "Incorrect parameter : start/stop/status\n";
    }
}

#Call the methods to start the server
sub start
{
    #createFifo();
    if(-e ".IBWS")
    {
        print "Already started !\n";
        exit 0;
    }
    configLoad(\$routes,\$confs);
    createLogFile($confs);
    startServer($confs, $routes);
}

#Stop the server
sub stop
{
    if(! -e ".IBWS")
    {
        print "Already stopped !\n";
        exit 0;
    }

    open(READ, ".IBWS") or die "open : $!";
my    $pidPere = <READ>;
my    $logFile_name = <READ>;
my    $port = <READ>;
    chomp($logFile_name, $port, $pidPere);
    kill(15,$pidPere);
    close READ;
    unlink(".IBWS");

    
    #TODO createLogFile($confs);
    #TODO writeLog("stop", "local", $port, "", "");
    print "Server stopped !\n";
    exit 0;
}

#Print the server's status
sub status
{
    writeStatus();
}

#Initialize the handler
sub startServer{
	my ($confs,$routes) = @_;
	#jbdebug
	print Dumper(('---- in start server ---- confs is ---', $confs));
    my $pid = fork();
    #Le père se quitte, le fils va créer le listener et instancier un autre fils par requête à partir d'ici.
    if($pid == 0){
        $requetesR = 0;
        $requetesT = 0;
        $mainPid = $$;
        writeFile();
        my @fils = ();
        my $sock = IO::Socket::INET->new(Listen    => $MAX_LISTEN,
                                         LocalAddr => '0.0.0.0',
                                         LocalPort => $confs->{"port"},
                                         Proto     => 'tcp')
            or die "Cannot create socket - $IO::Socket::errstr\n";
        $sock->autoflush(1);
        while(1){
            readRequest($sock, \@fils, $confs,$routes);
            if(scalar @fils > 0){
                my $mort;
                while($mort = waitpid(-1, WNOHANG)){
                    my $index = 0;
                    $index++ until $fils[$index] eq $mort;
                    splice(@fils, $index, 1);
                    sigRequestDone();
                }
            }
            writeFile();
        }
        close($sock);
    }else{
        print "Server started !\n";
        writeLog("start", "local", $confs->{"port"}, "", "");
        exit 0;
    }
}

#Initialize the confs.
sub order{
	my ($given_order, $routes, $confs) = @_;
	
	print Dumper('---- in order ----', $given_order, $routes, $confs);
	
    if($given_order =~ s/^set ([\w]+)/$1/g) {
        my @order = split(/ /,$given_order);
        my @variables = ("port", "error", "index", "logfile", "clients");
        #Verification de la variable
        grep(/^$order[0]/, @variables) or die "Invalid variable : $!";
        $confs->{$order[0]} = $order[1];
    }
    else {
        my @order = split(/ /,$given_order);
        if($order[0] eq "route") {
            #Regexp1 comme clef, Regexp2 comme valeur:
            $order[2] eq "to" or die "Invalid route : $!";
            $confs->{"route"}{$order[1]} = $order[3];
            push @$routes, $order[1];
        }
        else
        {
            #Regexp1 comme clef, Regexp2 comme valeur:
            $order[2] eq "from" or die "Invalid route : $!";
            $confs->{"exec"}{$order[1]} = $order[3];
            push @$routes, $order[1];
        }
    }
}

#Load the configutation file.
sub configLoad
{
	my ($routes,$confs) = @_;
	my $config_info = read_file($CONFIG_FILE);
	$$confs = (decode_json($config_info));
	$$routes = ($$confs->{'routes'});
	print Dumper('--- confs routes----', $$confs,$$routes);
	return;
=begin	
	die('dead');
    #Hashmap des ordres:
    #%confs;
    $confs->{"port"} = 8080;
    $confs->{"error"} = "";
    $confs->{"index"} = "";
    $confs->{"logfile"} = "";
    $confs->{"clients"} = 1000;
    #@routes = ();


    #Ouverture du fichier de config
    open(CONFIG, "comanche.conf") or die "open: $!";

    #Fixation des variables
    while(<CONFIG>) {
        #Suppression des espaces
        s/^[ \t]+//g;
        #Suppression des commentaires
        s/#*//g;

        if(!/^[\s\n]+/) {
            chomp;
            my $order = $_;
            print Dumper('---- this order ----',$order);
            #Verification de l'ordre
            ($order =~ /^set|^route|^exec/) or die "Invalid order: $!";
            #Ajout a la hashmap correspondante
            order ($order, \@routes,$confs);
        }
    }
=cut
}

sub readRequest{
    #Requete
    my ($listen_sock, $fils, $confs,$routes) = @_;
    my $chunk_size = 1024;
    #listen(SERVER, SOMAXCONN) or die "Listen : $!";
    my ($client, $iaddr) = $listen_sock->accept();

    #jbdebug
    print Dumper('---- peer address----', $iaddr, $client);

    #$addrinfo = accept(CLIENT, SERVER);
    #($port, $iaddr) = sockaddr_in($addrinfo);
    #$ipClient = gethostbyaddr($iaddr, AF_INET);

    $requetesR++;

    if( @$fils > $confs->{"clients"}){
        $client->send(sendError(503));
        sigRequestDone();
        $client->shutdown(SHUT_RDWR);
    }
    else{
        my $pidReq = fork();
        push @fils, $pidReq if ($pidReq != 0);
        my $headers = {};
        if($pidReq == 0){
            my @received;
            my $chunk;
            my $lines;
            my $left_from_previous_chunk = '';
            my $max_loops = 1000;
            my $loop_counter = 0;
            my $saw_empty_line = 0;
            while (1){
                #get header
                $loop_counter +=1;
                my $rslt = $client->recv($chunk,$chunk_size);
                #jbdebug
                print Dumper('--- just read -----',$rslt, $chunk);
                my @new_rslts = split(/[\r]/,$left_from_previous_chunk . $chunk);
                #jbdebug
                print Dumper('--- new rslts -----',@new_rslts);
                my $num_lines = @new_rslts;
                if ($num_lines > 1){
                  for  (my $i = 0; $i < ($num_lines - 1) ; $i++){
                  	  my $next_line = $new_rslts[$i];
                  	  $next_line =~ s/^[\n]|[\n]$//;
                  	  if (0 == length($next_line)){
                  	  	$saw_empty_line = 1;
                  	  }
                  	  print Dumper('------ next line ----', $next_line);
                      push @received,$next_line
                  }
                  my $next_line = $new_rslts[$num_lines - 1];
                  $left_from_previous_chunk = $next_line;
                  $next_line =~ s/^[\n]|[\n]$//;
                  print Dumper('------ next line x ----', $next_line);
                  if (0 == length($next_line)){
                  	$saw_empty_line = 1;
                  }
                }elsif (1 == $num_lines){
                  my $next_line = $new_rslts[0];
                  $left_from_previous_chunk = $next_line;
                  $next_line =~ s/^[\n]|[\n]$//;
                  print Dumper('------ next line xx ----', $next_line);
                  if (0 == length($next_line)){
                  	$saw_empty_line = 1;
                  }
                }else{ #0 == $num_lines
                    my @new_rslts = split(/[\r]/,$left_from_previous_chunk);
                      for  (my $i = 0; $i < (@new_rslts) ; $i++){
                  		my $next_line = $new_rslts[$i];
                  		$next_line =~ s/^[\n]|[\n]$//;
                  		print Dumper('------ next line xxx ----', $next_line);
                  		if (0 == length($next_line)){
                  			$saw_empty_line = 1;
                  		}
                        push @received,$next_line
                      }
                }
                if ($saw_empty_line){
                    add_headers($headers,\@received );
                    last;
                }
                #final bit
                if (!$rslt){
                    add_headers($headers,\@received );
                    last;
                }
                #fail safe
                if ($loop_counter > $max_loops){
                    print ("too many trips to client \n");
                    last;
                }
            }
            my @get = split(/[ ]/,$received[0]);
            if (@get >=3){
            	$headers->{'_method'} = lc $get[0];
            	$headers->{'_uri'} = $get[1];
            	$headers->{'_http_version'} =  $get[2];
            }
            if ('post' eq lc($headers->{'_method'})){
                my $content_length =$headers->{'content-length'} + 0;
                my $to_receive = $content_length - length($left_from_previous_chunk);
                my $chunk ='';
                if($to_receive > 0){
                	my $rslt = $client->recv($chunk,$to_receive);
                }
            	$headers->{'_content'} =  $left_from_previous_chunk . $chunk;
            }
            print Dumper('----- received -----', @received);
            print Dumper('----- headers -----', $headers);
			#die('dead');
            #Vérification de la validité de la requpête:
            if(validateRequest($headers) != 0)
            {
                #$path = $get[1];

                my $chemin = projectionsCheck($headers,$routes,$confs);

                #Envoie une erreur 404 ou un succes selon le résultat de la recherche du fichier
                if (!$chemin)
                {
                    $client->send(sendError(404));
                }
                else
                {
                    my $to_send = checkPath($chemin,$confs);
                    print Dumper('---- to send ----', $to_send);
                    my $err = $client->send($to_send);
                    print "-----------sent response -----, $err\n";
                }
            }
            $client->shutdown(SHUT_RDWR);
            #TODO : Faire fonctionner les signaux
            #print "mainPid : $mainPid\n\n";
            #kill(USR1,$mainPid);
            exit 0;
        }
    }
}

#Check the request's validity
sub validateRequest
{
	my ($headers) = @_;
    #jbdebug
    return 1;
=begin
    #s/\r//g for @get;
    #if((scalar @get != 3) || ($get[0] ne "GET") || ($get[2] ne "HTTP/1.1"))
    if($get[2] ne "HTTP/1.1")
    {
        if($get[2] ne "HTTP/1.1")
        {
            print CLIENT sendError(505);
        }
        return 0;
    }
    return 1;
=cut
}

#Check the projections and change the path if it matches one on them
sub projectionsCheck{
	my ($headers,$routes,$confs) = @_;
	my $path = $headers->{'_uri'};
    my $chemin = undef;
    #Parcours des projections spécifiées dans le config, comparaison avec la ressource demandée
    #Si une des projection correspond, elle est utilisée pour construire la réponse:

    #jbdebug
    print Dumper('---routes ----',$routes);
    for my $route (@$routes){
        #jbdebug
        print Dumper ('--- path, route ---', $path,  $route, "\n");
		#jbdebug
		my $route_key = $route->{'the_key'};
		$path =~ qw{^([/])(.*)([/]*)} ;
		my $path_key;
		if ($2){
			$path_key = $2;
			print Dumper('---- path key----', $path_key);
		}elsif ($1){
			$path_key = $1;
		}
		#uri, query string
		my $uri;
		my $query_string;
		$path =~ qw{([^?]+)([?]*)(.*)$} ;
		if ($1){
			$uri = $1;
		}
		if ($3){
			$query_string = $3;
		}
		
        if($path_key =~ /$route_key/){
        	$chemin = $route;
        	$chemin->{'_uri'} = $uri;
        	$chemin->{'_query_string'} = $query_string;
        	print Dumper('----route key path----',$route_key,$path,$chemin);
        	last;
        	my $routeExec;
            if(exists $confs->{"route"}{$route})
            {
                $routeExec = "route";
            }
            elsif(exists $confs->{"exec"}{$route})
            {
                $routeExec = "exec";
            }
            else
            {
                next;
            }
            $chemin = $confs->{$routeExec}{$route};
            $chemin =~ s!\/+!\/!g;

            my $routeTmp = qr/$route/;
            $_ = $path;

            my @matches = m/$routeTmp/;

            for my $m (@matches) {
                #my $m = $matches[$i++];
                #TODO$chemin =~ s{\\$i}{$m};
            }
            m/$chemin/;
            last;
        }
    }
    print Dumper("returning chemin ", $chemin, "\n");
    return $chemin;
}

#Check the path, redirect it depending on his nature.
sub checkPath
{
    my $response;

    my ($pathinfo, $confs) = @_;
    my $path;

    #jbdebug
    print Dumper ('---- pathinfo  is ----',$pathinfo, "\n");
    
    #we have a file
    if ($pathinfo->{'filename'}){
    	$path = $pathinfo->{'filename'};
    	if ($pathinfo->{'dir'}){
    		$path = sprintf("%s/%s",$pathinfo->{'dir'},$path);
    	}
    }
	my $is_text = $pathinfo->{'is_text'};
	my $mime = $pathinfo->{'mime'};
	#jbdebug
	print Dumper("using path $path .... $mime");
    #static html file
    if (-e $path and $is_text and $mime){
		return  ($response = sendOk($path, $mime));
    }

	#error: xyz ...
    if (! -e $path)
    {
        return ($response = sendError(404));
    }
    else
    {
        #Si dossier :
        if( -d $path)
        {
            #On retourne le fichier "index" si il existe
            if ( -e "$path"."$confs->{\"set\"}{index}")
            {
                $path = "$path"."$confs->{\"set\"}{index}";
                $response = sendOk($path, "text/html");
            }
            else
            {
                #On retourne le contenu du dossier sinon
                $path = listElements($path);
                $response = sendOk($path, "text/html");
            }
        }
        else
        {
            #Si fichier : on vérifie son type et on le retourne si il est dans la liste des types supportés, sinon on affiche une erreur 415 (Unsupported Media Type).
            my @ext = ("html", "png", "txt");
            my $ex =(split(/\./, "$path"))[-1];

            if ( $ex eq 'exe')
            {
                $path = `export METHOD=GET;$path`;
                $response = sendOk($path, "text/html", 1);
            }
            elsif(grep{/$ex/i} @ext)
            {
                my $mime;
                if($ex eq "html")
                {
                    $mime = "text/html";
                }
                elsif($ex eq "png")
                {
                    $mime = "image/png";
                }
                elsif($ex eq "txt")
                {
                    $mime = "text/plain";
                }
                $response = sendOk($path, $mime);
            }
            else
            {
            $response = sendError(415);
            }
        }
    }
    print Dumper('---returning----', $response);
    return $response;
}

#Create a simple HTML page listing all the elements of the given directory.
sub listElements
{
    my $path = $_[0];
    my $list = "$path"."list.html";
    open(my $fh, '>', $list) or die "Open : $list :  $!";

    print $fh "<html>\n\t<head>\n\t\t<title>Liste elements</title>\n\t</head>\n\t<body>\n\t\t<center>\n\t\t\t<h1>Liste elements</h1>\n\t\t\t<ul>";
    foreach my $file (glob("$path/*"))
    {
        $file = (split(/\//, "$file"))[-1];
        print FILE "\n\t\t\t\t<li><a href=\"$file\">$file</a></li>";
    }

    print FILE "\n\t\t\t</ul>\n\t\t</center>\n\t</body>\n</head>";

    close(FILE);
    return $list;
}

#Send the correct response, with the correct mime type.
sub sendOk
{
	my $ipClient = 'TBD';
    #jbdebug
    print Dumper('--sendOK called---',@_);
    my $response;

    #On a vérifier que le fichier existe avant de l'envoyer ici
    my ($path,$mime,$path_is_str) = @_;
    #Ligne de statut : VERSION CODE PHRASE\r\n
    $response = "HTTP/1.1 200 \"OK\"\r\n";
    #En-tete de reponse :
    $response .= "Content-type: $mime\r\n";
    my $taille = -s $path;
    $response .= "Content-Length: $taille\r\n";
    $response .= "Connection: close\r\n";
    $response .= "\r\n";
    #Reponse :
    if (not $path_is_str){
        open(HANDLE, '<', $path) or die "Open : $path  $!";
        while(<HANDLE>)
        {
            $response .= $_;
        }
        close(HANDLE) or die "Close : $!";
   }else{
       $response .= $path;
   }
    #$response .= "\r\n";
    writeLog("get-s", $ipClient, "\@get", "$path", "200");

    return $response;
}

#Send an error message. Could be 200, 400, 403, 404, 405, 415, 503 or 505.
sub sendError
{
    my $response;
    my $ipClient = 'TBD';
    my @get = ('To be determined');
    my $errorPage;
    my $size;
    my $taille;
	#global $confs
    if($_[0] == 400)
    {
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response = "HTTP/1.1 400 \"Bad Request\"\r\n";

        #En-tete de reponse :
        $response .= "Content-type:text/html\r\n";
        $response .= "Content-Length:11\r\n";

        $response .= "\r\n";
        #Reponse :
        $response .= "Bad Request\r\n";
        writeLog("get-s", $ipClient, "@get", "", "400");
    }
    elsif($_[0] == 404)
    {
        #Requête 404:
        #Pour le fichier final :
        #jbdebug
        print Dumper('---- doing error 404 ---------');
        if($confs->{"route"}{"error"} != undef)
        {
            $errorPage = $confs->{"route"}{"error"};
            $size = -s $errorPage;
        }
        else
        {
            $errorPage = "error.html";
            $size = -s $errorPage;
        }
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response =  "HTTP/1.1 404 \"Not Found\"\r\n";

        #En-tete de reponse :
        $response .=  "Content-type:text/html\r\n";
        $taille = -s $errorPage;
        $response .=  "Content-Length:$taille\r\n";

        $response .=  "\r\n";
        #Reponse :

        open(HANDLE, '<', $errorPage) or die "Open : $!";
        while(<HANDLE>)
        {
            $response .= $_ ;
        }
        close(HANDLE) or die "Close : $!";
        $response .= "\r\n";
        writeLog("get-s", $ipClient, "@get", "$errorPage", "404");
    }

    elsif($_[0] == 405)
    {
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response = "HTTP/1.1 405 \"Method Not Allowed\"\r\n";

        #En-tete de reponse :
        $response .=  "Content-type:text/html\r\n";
        $response .=  "Content-Length:18\r\n";

        $response .=  "\r\n";
        #Reponse :
        $response .=  "Method Not Allowed\r\n";
        writeLog("get-s", $ipClient, "@get", "", "405");
    }
    elsif($_[0] == 415)
    {
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response = "HTTP/1.1 415 \"Unsupported Media Type\"\r\n";

        #En-tete de reponse :
        $response .=  "Content-type:text/html\r\n";
        $response .=  "Content-Length:22\r\n";

        $response .=  "\r\n";
        #Reponse :
        $response .=  "Unsupported Media Type\r\n";
        writeLog("get-s", $ipClient, "@get", "", "415");
    }
    elsif($_[0] == 503)
    {
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response =  "HTTP/1.1 503 \"Service Unavailable\"\r\n";

        #En-tete de reponse :
        $response .=  "Content-type:text/html\r\n";
        $response .=  "Content-Length:19\r\n";

        $response .=  "\r\n";
        #Reponse :
        $response .=  "Service Unavailable\r\n";
        writeLog("get-s", $ipClient, "@get", "", "503");
    }
    elsif($_[0] == 505)
    {
        #Ligne de statut : VERSION CODE PHRASE\r\n
        $response .=  "HTTP/1.1 505 \"HTTP Version Not Supported\"\r\n";

        #En-tete de reponse :
        $response .=  "Content-type:text/html\r\n";
        $response .=  "Content-Length:26\r\n";

        $response .=  "\r\n";
        #Reponse :
        $response .=  "HTTP Version Not Supported\r\n";
        writeLog("get-s", $ipClient, "@get", "", "505");
    }

    return $response;
}

#Check if the logfile parameter is valid, then create the file or use it if he already exist
sub createLogFile
{
	my ($confs) = @_;
	#global confs
    $logFile = $confs->{"logfile"};
    $logFile = "comanche.log" if(! (-f $logFile));

    print Dumper('---- in create logfile-----', $logFile);

    open(LOGFILE, ">>$logFile") or die "Open logFile : $!";

    close LOGFILE or die "Close logFile : $!";
}

#Write a new log line.
#Parameters : "Type" - "Source" - "Request" - "Path" - "Response"
sub writeLog
{
    my $date = time();
    my $type = shift;
    my $src = shift;
    my $req = shift;
    my $path = shift;
    my $response = shift;

    open(my $LOGFILE, ">>$logFile") or die "Open logFile : $!";

    print $LOGFILE "$date;$type;$src;$req;$path;$response;\n";

    close $LOGFILE or die "Close logFile : $!";
}

sub writeStatus
{
    #TODO : Remplacer la leture de fichier par un signal au processus principal + ouverture de tube.
    open(READ, ".IBWS") or die "open : $!";
    my $pid = <READ>;
    my $tmp = <READ>;
    $tmp = <READ>;
    my $requetes = <READ>;
    my $fils = <READ>;
    print "PID du processus principal : \t\t$pid";
    print "Nombre de requêtes traitées / reçues : \t$requetes";
    print "Nombre d'ouvriers actifs + liste : \t$fils";
    exit 0;
}

#Check if the fifo exists, exit the program in this case, create it and write the pid otherwise.
sub createFifo
{
    if (-e $fifopath)
    {
        print "Already started !\n";
        exit 0;
    }
    mkfifo($fifopath, 0644) or die "mkfifo : $!";
    open (WRITE, ">$fifopath") or die "open fifo : $!";
    WRITE->autoflush(1);
    print WRITE "$$\n";
    close WRITE;
}

#Function called when a son has finished his job.
sub sigRequestDone
{
    $requetesT++;
}

#TODO : Supprimer une fois le fifo fonctionnel
sub writeFile
{
 	#global confs
    open(FILE, ">.IBWS") or die "open : $!";
    print FILE "$mainPid\n";
    print FILE $confs->{"logfile"},"\n";
    print FILE $confs->{"port"},"\n";
    print FILE $requetesT."/".$requetesR."\n";
    print FILE scalar @fils." @fils\n";
    close FILE;
}

sub add_headers{
    my($headers,$lines) = @_;
    for my $line (@$lines){
        my ($key, $value) = $line =~ /([^:]+)[:]\s+(.+)$/;
        if ($key and $value) {
            $value =~ s/\r\n/NNLL/g;
            $headers->{lc $key} = $value;
        }
    }
}
