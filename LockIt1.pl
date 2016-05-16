#!/usr/bin/perl
use strict;
#use warnings FATAL => 'all';
use Date::Calc qw(Add_Delta_DHMS);
use Fcntl qw(:flock SEEK_END);
use IO::File;
use File::Path qw( make_path );


my $ENABLE_FILE_LOCKING;
my $ENABLE_FILE_LOCK_LOGGING;

# calculate the start date
my $now   = get_current_time_for_logging();
print "\nStarting at $now\n";

my $status           = 'success';
my $reason           = "";
my $error            = 0;
my $LOCK_FAILURE_STATUS	= 'ALREADY RUNNING';
my $wait_intervals  = 60;


# set up lock files so that we can singleton this process
my $test_folder = '/data/feeds/outgoing/test/';
my $lock_file	= "$test_folder/feeds_file_lock";

# make sure that we have the test path
if ( not -d $test_folder ) {
    print "Creating test folder, $test_folder - does not yet exist\n";
    make_path( "$test_folder" );
}

my $return_code;
my $err_txt;
my $fh	= open_and_lock_without_waiting( $lock_file );
$now   = get_current_time_for_logging();

if ( $fh  and ref $fh eq 'IO::File' ) {
    # We have a good file handle with lock, go do stuff
    print "$now Got file lock - lets do stuff.....\n";
    my $interval_time   = 3; # seconds
    my $interval_count;
    while ( $interval_count++ <= $wait_intervals ) {
        $now   = get_current_time_for_logging();
        my $msg = "$now $interval_count - work work work...";
        print "$msg\n";
        sleep $interval_time;
    }

} else {
    # DID NOT GET LOCK ON UNIT FILE - Already running
    $error	= 1;
    $status	= $LOCK_FAILURE_STATUS;
    $reason	= "FAILED TO GET FILE LOCK";
    $err_txt	= "Horrible death in error";
    $now   = get_current_time_for_logging();
    my $msg = "$now $err_txt $reason";
    print "\n\n$msg\n\n";
}

exit;


# METHODS ###
sub get_current_time_for_logging {
    my ($second, $minute, $hour, $day, $month, $year) = localtime(time);
    my @window = (-1, 0, 0, 0);
    my ($year2, $month2, $day2, $h2, $m2, $s2) = Add_Delta_DHMS($year + 1900, $month + 1, $day, $hour, $minute, $second, @window);
    my $printable_time = sprintf('%d/%02d/%02d %02d:%02d:%02d', $year2, $month2, $day2, $h2, $m2, $s2);
    return $printable_time;
}

# Opens a file and performs proper exclusive file locking
sub open_and_lock_without_waiting {
    my ($file) = @_;

    ### Lazy-init config env specific config values if we haven't yet
    #    unless (defined $ENABLE_FILE_LOCKING && defined $ENABLE_FILE_LOCK_LOGGING) {
    #        $ENABLE_FILE_LOCKING      = NYT::Feeds::ApplicationConfiguration->get_value('ENABLE_FILE_LOCKING');
    #        $ENABLE_FILE_LOCK_LOGGING = NYT::Feeds::ApplicationConfiguration->get_value('ENABLE_FILE_LOCK_LOGGING');
    #    }
    # Just force this
    $ENABLE_FILE_LOCKING	= 1;
    $ENABLE_FILE_LOCK_LOGGING	= 1;

    # mode info
    my $mode	= 'w';
    my $mode_verbose = 'write';
    my $lock_type = LOCK_EX | LOCK_NB;
    my $max_tries		= 2;

    # The basic file open/create
    my $fh = IO::File->new($file, $mode);
    if ( defined $fh ) {
        # But if locking, then we have more to do
        if ( $ENABLE_FILE_LOCKING ) {
            # what form of locking?
            $ENABLE_FILE_LOCK_LOGGING and print "\n\nFile Lock: Attempting to get $mode_verbose-lock on $file\n\n";

            # Do the actual lock
            my $lock_tries		= 1;
            my $error_on_lock	= 0;
            eval { flock(  $fh, $lock_type) or $error_on_lock = 1 };
            # We need to do our own waiting since flock is not always pretty against NFS
            while ( ($@ or $error_on_lock ) and ( $lock_tries++ <= $max_tries ) ) {
                $error_on_lock	= 0;
                eval { $error_on_lock = flock( $fh, $lock_type) };
            }

            if ( $lock_tries < $max_tries ) {
                $ENABLE_FILE_LOCK_LOGGING and print "File Lock: Aquired $mode_verbose-lock $file in $lock_tries tries\n\n";
            } elsif ( $error_on_lock ) {
                $fh	= 0;
                $ENABLE_FILE_LOCK_LOGGING and print "\n\nFile Lock: Forced aquired $mode_verbose-lock $file after $lock_tries tries\n\n";
            } else {
                $ENABLE_FILE_LOCK_LOGGING and print "\n\nFile Lock: Can't get $mode_verbose-lock on $file: $!\n\n";
                $fh = 0;
            }
        }
    } else {
        # Failed to even open the filehandle - get the word out
        $ENABLE_FILE_LOCK_LOGGING and print "\n\nFile Lock unable to open $file: $!\n\n";
    }

    return $fh;
}



sub close_and_release_lock {
    my ($filehandle, $filename) = @_;

    ### Lazy-init config env specific config values if we haven't yet
    unless (defined $ENABLE_FILE_LOCKING && defined $ENABLE_FILE_LOCK_LOGGING) {

        print "\n\nJRS UNDEFINED VALUES AT POINT.122\n\n";
        #        $ENABLE_FILE_LOCKING      = NYT::Feeds::ApplicationConfiguration->get_value('ENABLE_FILE_LOCKING');
#        $ENABLE_FILE_LOCK_LOGGING = NYT::Feeds::ApplicationConfiguration->get_value('ENABLE_FILE_LOCK_LOGGING');
    }

    eval { flock( $filehandle, LOCK_UN ) or die "Cannot unlock mailbox - $!\n" };
    if ( $@ or defined $filehandle ) {
        $filehandle->close();
    }

    if ($ENABLE_FILE_LOCKING && $ENABLE_FILE_LOCK_LOGGING) {
        print "File Lock: Released lock on $filename";
    }

    return 1;
}







