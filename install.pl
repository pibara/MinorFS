#!/usr/bin/perl
#MinorFs POLP/POLA proof of concept filesystem kit
#Copyright (C) Rob J Meijer 2008 2009 <minorfs@polacanthus.net>
#
#This library is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation; either
#version 2.1 of the License, or (at your option) any later version.
#
#This library is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#Lesser General Public License for more details.
#
#You should have received a copy of the GNU Lesser General Public
#License along with this library; if not, write to the Free Software
#Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
use strict;
use User::pwent;
use Digest::SHA1;
use POSIX qw(ENOENT ENOSYS EEXIST EPERM O_RDONLY O_RDWR O_APPEND O_CREAT);
my $configok=1;
foreach my $module ("Unix::Mknod qw(:all)","Fuse qw(fuse_get_context)","Digest::SHA1","XML::DOM","File::ExtAttr","IO::File","POSIX qw(ENOENT ENOSYS EINVAL EEXIST EPERM O_RDONLY O_RDWR O_APPEND O_CREAT)","Fcntl qw(S_ISBLK S_ISCHR S_ISFIFO SEEK_SET)","Proc::DaemonLite","DBI") {
   eval "use $module;\n";
   if ($@) {
     my $pmodule = $module;
     $pmodule =~ s/\s.*//;
     print STDERR "ERROR: $pmodule perl module not installed\n";
     $configok=0;
   }
}
if ($configok) {
  print "OK: all required perl modules are found\n";
}
my $sqlite=`which sqlite3`;
$sqlite =~ s/\r//g;
chomp($sqlite);
unless ($sqlite) {
  print STDERR "ERROR: sqlite3 not installed\n";
  $configok=0;
}
unless (open(LSMOD,"/bin/lsmod|")) {
  print STDERR "ERROR: Unable to run lsmod, can't determine if fuse is available\n";
  $configok=0;
} else {
  my $fuseok=0;
  while (<LSMOD>) {
    if (/^fuse\s+/) {
      $fuseok=1;
    } 
  }
  if ($fuseok == 0) {
    $configok=0;
    print STDERR "ERROR: The fuse kernel module does not seem to be loaded, it should be loaded at boot time.\n";
  }
}
if ($configok) {
  print "OK: The fuse kernel module is loaded\n";
}
if ($> != 0) {
  print STDERR "ERROR: You should run install as root\n";
  $configok=0;
}
my $RCAPPARMOR = `which rcapparmor`;
$RCAPPARMOR =~ s/\r//g;
chomp($RCAPPARMOR);
unless ($RCAPPARMOR) {
  if (-f "/etc/init.d/apparmor") {
     $RCAPPARMOR="/etc/init.d/apparmor";
  }
  else {
     print "STDERR: No AppArmor found\n";
     $configok=0;
  }
}
unless ($configok) {
  print "Aborting install, fix the abouve problems first\n";
  exit 1; 
}
print "OK: All precondition checks succeeded\n";
unless (open(GROUP,"/etc/group")) {
  print STDERR "ERROR: Can not open /etc/group file, aborting install\n";
  exit 1;
}
my $minorgid = 0;
my $minorgroup="minorfs";
while (<GROUP>) {
  if (/^fuse:.:(\d+):/) {
     $minorgid=$1;
     $minorgroup="fuse";
  }
}
close(GROUP);
unless ($minorgid) {
  print "Creating new group minorfs if non exists\n";
  my $ignore=`groupadd minorfs`;
  unless (open(GROUP,"/etc/group")) {
     print STDERR "ERROR: Can not open /etc/group file, aborting install\n";
     exit 1;
  }
  while (<GROUP>) {
    if (/^minorfs:.:(\d+):/) {
      $minorgid=$1;
    }
  }
  close(GROUP);
}
unless ($minorgid) {
   print STDERR "Problem creating minorfs group, aborting install\n";
   exit 1;
}
foreach my $minoruser ("capfs","ctkrfs","rofs","cowfs") {
  if (my $pw=getpwnam($minoruser)) { 
    unless ($pw->gid == $minorgid) {
      print "ERROR: $minoruser exists but does not have $minorgroup as its primary group\n";
      exit 1;
    } else {
      print "OK: user $minoruser already exists\n";
    }
  } else {
    print "creating user $minoruser\n";
    my $result=`/usr/sbin/useradd -g $minorgid $minoruser`;
    print "$result";
    if (my $pw=getpwnam($minoruser)) {
      unless ($pw->gid == $minorgid) {
        print "ERROR: $minoruser creation ended up with a wrong gid, this should not hapen\n";
        exit 1;
      }
    } else {
      print "ERROR: problem creating new user\n";
      exit 1; 
    }
    print "OK: user $minoruser created\n";
  }
  my $ignore=`/usr/sbin/usermod -G fuse -a $minoruser`;
}
my $ignore=`/usr/sbin/usermod -G fuse -a root`;
my $pw2=getpwnam("capfs");
my $capfsuid=$pw2->uid;
$pw2=getpwnam("ctkrfs");
my $ctkrfsuid=$pw2->uid;
print "CAPFS=$capfsuid\n";
print "CNTLFS=$ctkrfsuid\n";
my $ETCDIR="/etc/minorfs";
my $MOUNTROOT="/mnt/minorfs";
my $VARDIR="/var/minorfs";
foreach my $sysdir ($ETCDIR,$MOUNTROOT,$VARDIR) {
  mkdir($sysdir,0750);
  chown(0,$minorgid,$sysdir);
  chmod 0750, $sysdir;
  unless (-d $sysdir) {
    print "ERR: problem creating $sysdir\n";
    exit 1;
  }
}
chown(0,$minorgid,$VARDIR);
chmod(0755,$MOUNTROOT);

opendir(ETC,"etc")|| die "You must run this script from the distribution dir";
my @etcfiles = readdir(ETC);
closedir(ETC);
foreach my $xmlfile (@etcfiles) {
  if ($xmlfile =~ /\.xml/) {
    open(IN,"etc/$xmlfile");
    open(OUT,">${ETCDIR}/$xmlfile");
    while(<IN>) {
      print OUT "$_";
    }
    close(IN);
    close(OUT);
  }
}
print "OK: copied etc files to $ETCDIR\n";

foreach my $mountpoint ("priv","cap","ctkr","ro","cow") {
  mkdir("$MOUNTROOT/$mountpoint",0750);
  chown(0,$minorgid,"$MOUNTROOT/$mountpoint");
}
chmod(0750,"$MOUNTROOT/priv");
chmod(0770,"$MOUNTROOT/cap");
chmod(0770,"$MOUNTROOT/ctkr");
chmod(0770,"$MOUNTROOT/ro");
chmod(0770,"$MOUNTROOT/cow");

print "OK: Created mountpoints in $MOUNTROOT\n";

mkdir("$VARDIR/stub",0700);
chown($capfsuid,$minorgid,"$VARDIR/stub");
chmod(0100,"$VARDIR/stub");


foreach my $varsub ("capfs","capfs/data","capfs/data/user") {
  mkdir("$VARDIR/$varsub",0700);
  chmod(0700,"$VARDIR/$varsub");
  chown($capfsuid,$minorgid,"$VARDIR/$varsub");
}



mkdir("$VARDIR/ctkrfs",0700);
chmod(0700,"$VARDIR/ctkrfs");
chown($ctkrfsuid,$minorgid,"$VARDIR/ctkrfs");


unless (-f "$VARDIR/capfs/secret") {
  `/bin/dd if=/dev/urandom of=$VARDIR/capfs/secret bs=1024 count=1`;
  chown($capfsuid,$minorgid,"$VARDIR/capfs/secret");
  chmod(0400,"$VARDIR/capfs/secret");
}

unless (-f "$VARDIR/ctkrfs/secret") {
  `/bin/dd if=/dev/urandom of=$VARDIR/ctkrfs/secret bs=1024 count=1`;
  chown($ctkrfsuid,$minorgid,"$VARDIR/ctkrfs/secret");
  chmod(0400,"$VARDIR/ctkrfs/secret");
}

my $SECRET;
 unless ( sysopen(SECRET,"${VARDIR}/capfs/secret",O_RDONLY) ) {
   die "Problem with opening secret ${VARDIR}/capfs/secret";
   exit 1;
}
sysread(SECRET,$SECRET,1024);
close(SECRET);

open(SQLITE,"|$sqlite $VARDIR/capfs/rwcap.db");
print SQLITE "create table passcaps (passcap varchar,path varchar);\n";
foreach my $createpath ("$VARDIR/capfs/data","$VARDIR/capfs/data/user") {
  my $sha1 = Digest::SHA1->new;
  $sha1->add($createpath);
  $sha1->add($SECRET);
  my($digest)= $sha1->hexdigest;
  print SQLITE "INSERT INTO passcaps (passcap,path) VALUES('$digest','$createpath');\n";
  if ($createpath eq "$VARDIR/capfs/data/user") {
    open(VIEWCAP,">$VARDIR/viewfs.startcap");
    print VIEWCAP "$MOUNTROOT/cap/$digest\n";
    close(VIEWCAP);
    chmod(0400,"$VARDIR/viewfs.startcap");
  }
}
close(SQLITE);
chown($capfsuid,$minorgid,"$VARDIR/capfs/rwcap.db");
chmod(0600,"$VARDIR/capfs/rwcap.db");

open(SQLITE,"|$sqlite $VARDIR/ctkrfs/ctkr.db");

print SQLITE "CREATE TABLE control (\n";
print SQLITE "  control_id INTEGER PRIMARY KEY AUTOINCREMENT,\n";
print SQLITE "  anchorfs VARCHAR,\n";
print SQLITE "  anchorcap VARCHAR,\n";
print SQLITE "  petname VARCHAR,\n";
print SQLITE "  modemask INTEGER,\n";
print SQLITE "  UNIQUE (anchorfs,anchorcap,petname) ON CONFLICT ABORT\n";
print SQLITE ");";

print SQLITE "CREATE TABLE attnset (\n";
print SQLITE "  attncap VARCHAR PRIMARY KEY,\n";
print SQLITE "  control_id INTEGER CONSTRAINT fk_control_id REFERENCES control(control_id) ON DELETE CASCADE,\n";
print SQLITE "  basefs VARCHAR,\n";
print SQLITE "  basecap VARCHAR,\n";
print SQLITE "  primset BOOLEAN,\n";
print SQLITE "  nread BOOLEAN,\n";
print SQLITE "  nwrite BOOLEAN,\n";
print SQLITE "  sread BOOLEAN,\n";
print SQLITE "  swrite BOOLEAN,\n";
print SQLITE "  fread BOOLEAN,\n";
print SQLITE "  fwrite BOOLEAN,\n";
print SQLITE "  UNIQUE (control_id,basefs,basecap,primset) ON CONFLICT ABORT\n";
print SQLITE ");\n";
close(SQLITE);

chown($ctkrfsuid,$minorgid,"$VARDIR/ctkrfs/ctkr.db");
chmod(0600,"$VARDIR/ctkrfs/ctkr.db");

print "Building 2rulethemall\n";
my $result=`/usr/bin/make 2rulethemall`;
unless (-f "./2rulethemall") {
 print "Problem building 2rulethemall:";
 print " $result\n";
 print "Abborting install\n";
 exit 3;
}


print "Installing minorfs binaries\n";
foreach my $file ("minorviewfs","minorcapfs","2rulethemall") {
  print " * $file\n";
  `/bin/cp $file /usr/local/bin/`;
  unless (-f "/usr/local/bin/$file") {
     print "Problem copying $file to /usr/local/bin/ , abborting\n";
     exit 4;
  }
}
print "Installing rc script\n";
`cp rcscript /etc/init.d/minorfs`;
unless (-f "/etc/init.d/minorfs") {
  print "Problem copying ./rcscript to /etc/init.d/minorfs\n";
}
if (-d "/etc/apparmor.d") {
  print "Installing apparmor profiles\n";
  `cp -R apparmor.d/* /etc/apparmor.d`;
  unless (-f "/etc/apparmor.d/minorfs/base") {
     print "Problem copying apparmor profiles to /etc/apparmor.d\n";    
  }

} else {
  print STDERR "ERROR: No /etc/apparmor.d dir found, skipping apparmor profile install\n";
  print STDERR "ERROR: please note that without AppArmor you will only be able to use\n";
  print STDERR "ERROR: part of the functionality of MinorFs safely.\n\n";
}

unless (-f "/bin/bash") {
  print "No /bin/bash found\n";
  exit 1;
}
print "Restarting AppArmor with new profiles\n";
my $tmp=`$RCAPPARMOR restart`;
print "$tmp";
print "Creating /bin/minorbash as hardlink to /bin/bash\n";
link("/bin/bash","/bin/minorbash");
link("/bin/bash","/bin/minorbash_nopriv");
print "\n\nDONE\n\n";
print "WARNING: Don't forget to set a password for 2rulethemall for all relevant user accounts.\n";
