#!/usr/bin/perl

use strict;
use warnings;
use Try::Tiny;

my $BUILD="build";
my $ARTIFACT="artifact";

my $num_args = $#ARGV + 1;
if ($num_args < 1) {
    print "\nUsage: build_artifact.pl <git repository> [commit]\n";
    exit 1;
}

my $repo;
my $commit;

if(!defined $ARGV[0]){
    print "no repo specified!\n";
    exit 1;
} else {
    $repo=$ARGV[0];
}


if(!defined $ARGV[1]){
    $commit = "master";
} else {
    $commit=lc($ARGV[1]);
}

# global variable
my $builddir = "";
my $artifactdir = "";
my $logfile = "";
my $logfh;

my $reporegexp = '((git|ssh|http(s)?)|(git@[\w\.]+))(:(//)?)([\w\.@\:/\-~]+)(\.git)(/)?';
if($repo =~ m/$reporegexp/) {
    my $remote = $1;
    my $project = $7;
    
    $remote =~ s/git@([\w\.]+)/$1/;
    $remote =~ s/\./\//g;

    try {
        prep($remote, $project, $commit);
        cloning($repo, $builddir);
        checkout($builddir, $commit);
        replacegradlew($builddir); 
        checkgradle($builddir); 
        checktaskinstall($builddir); 
        runinstall($builddir, $remote, $project, $commit);
        extractartifacts($builddir, $artifactdir, $commit);
    } 
    catch {
        print "[!] an error occured: $_\n";
        cleanup($project);
    }
    finally {
        logfile("[+] done.");
        if($logfile ne "") {
            close($logfh);
        }
    }    
} else {
    print "[!] not a git repo";
    exit 1;
}

sub prep {
    my ($remote, $project, $commit) = @_;

    $artifactdir = "$ARTIFACT/$remote/$project";    
    die "artifact is already built" if ( -d $artifactdir );
    execute("mkdir -p $artifactdir");
    $logfile  = "$artifactdir/build.log";    
    open ($logfh, '>', $logfile) or die "Could not open file $logfile: $!";
   
    my $name = ( split '/', $project )[ -1 ];
    $builddir = "$BUILD/$remote/$project/$commit/$name";    
    execute("rm -rf $builddir");
    execute("mkdir -p $builddir");
}


sub cloning {
    my ($repo, $builddir) = @_;
    logfile("[+] cloning $repo... \n");
    execute("git clone $repo $builddir");
    die "unable to clone project: $repo" if $?; 
    logfile("[+] project cloned!\n");
}

sub checkout {
    my ($builddir, $commit) = @_;
    logfile("[+] checking out commit $commit ... \n");
    execute("cd $builddir && git reset --hard $commit");
    die("unable to checkout commit $commit!\n") if $?;
    logfile("[+] commit $commit checked out!\n");
}

sub replacegradlew {
    my ($builddir) = @_;
    execute("rm $builddir/gradlew");
    execute("rm -rf $builddir/gradle");
    execute("cp -r utility/gradlew/* $builddir/");
}

sub checkgradle {
    my ($builddir) = @_;
    my $buildgradle = "$builddir/build.gradle";
    die("no build.gradle") unless -e $buildgradle;
}

sub checktaskinstall {
    my ($builddir) = @_;
    logfile("[+] check gradle tasks..");
    execute("cd $builddir && ./gradlew tasks --all | grep install");
    if($?) {
        logfile("[+] adding plugin maven");
        execute("echo 'apply plugin: \"maven\"' >> $builddir/build.gradle");
    } else {
        logfile("[+] task install exists");
    }
}

sub runinstall {
    my ($builddir, $remote, $project, $commit) = @_;
    my $group = lc("$remote/$project");
    $group =~ s/\//\./g;
    logfile("[+] Running install gradle task");
    execute("cd $builddir && ./gradlew clean -Pgroup=$group -Pversion=$commit -xtest install");
}

sub extractartifacts {
    my ($builddir, $artifactdir, $commit) = @_;
    logfile("[+] Looking for artifacts in build folders...");
    my $findbuildcmd  = "find $builddir -name 'build' -type d \;";
    my $findbuildret = `$findbuildcmd`;
    my @listofbuildfolder = split /^/m, $findbuildret;

    while(my $buildfolder=shift(@listofbuildfolder)) {
        chomp($buildfolder);
        logfile("found build folder: $buildfolder, looking for artifacts...");
        my $findpomcmd = "find $buildfolder -name '*.jar' -type f \;";
        my $findpomret = `$findpomcmd`;
        my @listofartifact = split /^/m, $findpomret;

        $buildfolder =~ s/$builddir(\/.*)/$1/;
        $buildfolder =~ s/\/build//g;
        while(my $artifactpath=shift(@listofartifact)) {
            my $artifactname=( split '/', $artifactpath )[ -1 ];
            logfile("found artifact: ".$artifactdir.$buildfolder."/".$commit."/".$artifactname);
        }
    }
}


sub cleanup {
    my ($project) = @_;
    `rm -rf $builddir`;
}

sub execute {
    my ($ex) = @_;
    logfile("executing: $ex\n");
    my $execlog = `$ex 2>&1`;
    my $ret = $?;
    logfile("$execlog\n");
    return $ret;
}

sub logfile {
    my ($debug) = @_;
    chomp($debug);
    if($debug ne "") {
        print "$debug\n";
        if($logfile ne "") {
            print $logfh "$debug\n";
        }
    }
}
