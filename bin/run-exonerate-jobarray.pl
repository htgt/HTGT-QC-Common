#!/usr/bin/env perl
#
# $HeadURL: svn+ssh://svn.internal.sanger.ac.uk/repos/svn/htgt/projects/HTGT-QC/trunk/bin/run-exonerate-jobarray.pl $
# $LastChangedRevision: 7685 $
# $LastChangedDate: 2012-09-28 10:33:50 +0100 (Fri, 28 Sep 2012) $
# $LastChangedBy: vvi $
#

use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use Pod::Usage;

my @EXONERATE = qw( exonerate --bestn 1 --showcigar yes --showalignment yes );

my @BSUB = qw( bsub -R'select[mem>1000] rusage[mem=1000]' -M1000 -P team87 -q normal -o %J.%I.out );

GetOptions(
    'help'       => sub { pod2usage( -verbose => 1 ) },
    'man'        => sub { pod2usage( -verbose => 2 ) },
) and @ARGV > 2 or pod2usage(2);

my ( $model, $reads, @targets ) = @ARGV;

if ( $ENV{LSB_JOBINDEX} ) {
    my $target_ix = $ENV{LSB_JOBINDEX} - 1;
    die "LSB_JOBINDEX out of range"
        unless $target_ix >= 0 and $target_ix <= $#targets;
    my $target = $targets[$target_ix];
    my @cmd = ( @EXONERATE, '--model', $model, '--target', $target, '--query', $reads );
    exec @cmd
        or die "failed to exec exonerate: $!";
}else{
    die 'you cannot invoke this script outside a job-array: must have ENV{LSB_JOBINDEX} set';; 
}

#for ( $reads, @targets ) {
#    -r $_ or die "$_ is not readable";
#}
#
#my $jobspec = sprintf 'qc[1-%d]', scalar @targets;
#
#exec @BSUB, '-J', $jobspec, $0, $model, $reads, @targets;

__END__

=head1 NAME

run-exonerate-jobarray.pl - Describe the usage of script briefly

=head1 SYNOPSIS

run-exonerate-jobarray.pl [options] args

      -opt --long      Option description

=head1 DESCRIPTION

Stub documentation for run-exonerate-jobarray.pl, 

=head1 AUTHOR

Ray Miller, E<lt>rm7@sanger.ac.ukE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Ray Miller

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=head1 BUGS

None reported... yet.

=cut
