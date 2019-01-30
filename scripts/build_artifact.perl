#!/usr/bin/perl

use strict;
use warnings;
use Try::Tiny;
use XML::Parser;

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

sub checktaskinstall {
    my ($builddir, $artifactdir, $commit) = @_;
    logfile("[+] Looking for libraries ...");
    my $findbuildgradlecmd  = "find $builddir -name 'build.gradle' -type f \;";
    my $findbuildgradleret = `$findbuildgradlecmd`;
    my @listofbuildgradle = split /^/m, $findbuildgradleret;

    while(my $buildgradle=shift(@listofbuildgradle)) {
        if(haspattern($buildgradle, "java-library")) { 
            logfile("[+] found java library: $buildgradle");
            if(!haspattern($buildgradle, "'id.*?maven|plugin.*maven'")) {
                logfile("[+] adding plugin maven to: $buildgradle");
                execute("echo '\n\napply plugin: \"maven\"' >> $buildgradle");
            }
        }
        if(haspattern($buildgradle, "android-library") || haspattern($buildgradle, "com.android.library")) { 
            logfile("[+] found android library: $buildgradle");
            if(!haspattern($buildgradle, "'id.*?maven|plugin.*maven'")) {
                logfile("[+] adding plugin android-maven to: $buildgradle");
                execute("sed -i '1s/^/plugins { id \"com.github.dcendents.android-maven\" version \"2.1\" }\\n/' $buildgradle");
            }
        }
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
    my $findbuildcmd  = "find $builddir -name 'build' -type d";
    my $findbuildret = `$findbuildcmd`;
    my @listofbuildfolder = split /^/m, $findbuildret;

    while(my $buildfolder=shift(@listofbuildfolder)) {
        chomp($buildfolder);
        searchpom($buildfolder);
    }
}

sub searchpom {
    my ($buildfolder) = @_;

    my $findpomcmd = "find $buildfolder -name 'pom*' -type f";
    my $findpomret = `$findpomcmd`;
    my @listofpoms = split /^/m, $findpomret;

    while(my $pompath=shift(@listofpoms)) {
        chomp($pompath);
        buildartifact($buildfolder, $pompath);
    }
}

sub buildartifact {
    my ($buildfolder, $pompath) = @_;
    my $artifactid  = `cat $pompath|sed -ne '/artifactId/{s/.*<artifactId>\\(.*\\)<\\/artifactId>.*/\\1/p;q;}'`;
    my $packaging   = `cat $pompath|sed -ne '/packaging/{s/.*<packaging>\\(.*\\)<\\/packaging>.*/\\1/p;q;}'`;
    chomp($artifactid);
    chomp($packaging);

    my $reponame = ( split '/', $artifactdir )[ -1 ];
    my $artifactsubdir = $artifactdir;
    if($reponame ne $artifactid) {
        $artifactsubdir .= '/'.$artifactid.'/'.$commit;
    } else {
        $artifactsubdir .= '/'.$commit;
    }
    execute("mkdir -p $artifactsubdir");
    
    if($packaging eq "aar") {
        my $findbuildcmd = "find $buildfolder -name '$artifactid*aar' -type f -print -quit";
        my $findbuildret = `$findbuildcmd`;
        chomp($findbuildret);
        if($? == 0) {
            logfile("found artifact: ".$artifactsubdir."/".$artifactid."-".$commit.".aar");
            execute("cp $findbuildret $artifactsubdir/$artifactid-$commit.aar");
            execute("cp $pompath $artifactsubdir/$artifactid-$commit.pom");
            execute("md5sum $pompath > $artifactsubdir/$artifactid-$commit.pom.md5");
            execute("sha1sum $pompath > $artifactsubdir/$artifactid-$commit.pom.sha1");
        }
    } else {
        my $findbuildcmd = "find $buildfolder -name '$artifactid*jar' -type f -print -quit";
        my $findbuildret = `$findbuildcmd`;
        chomp($findbuildret);
        if($? == 0) {
            logfile("found artifact: ".$artifactsubdir."/".$artifactid."-".$commit.".jar");
            execute("cp $findbuildret $artifactsubdir/$artifactid-$commit.jar");
            execute("cp $pompath $artifactsubdir/$artifactid-$commit.pom");
            execute("md5sum $pompath > $artifactsubdir/$artifactid-$commit.pom.md5");
            execute("sha1sum $pompath > $artifactsubdir/$artifactid-$commit.pom.sha1");
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

sub haspattern {
    my ($file, $pattern) = @_;
    my $output = `grep -Eo $pattern $file`;
    return $? == 0;
}
