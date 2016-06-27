package HTGT::QC::Util::Which;

use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'which' ],
    groups  => {
        default => [ 'which' ]
    }
};

use File::Which ();
use HTGT::QC::Exception;

sub which {
    my $exe = shift;

    File::Which::which( $exe )
            || HTGT::QC::Exception->throw( "Failed to find executable $exe" );
}

1;

__END__

=pod

=head1 NAME

HTGT::QC::Util::Which

=head1 SYNOPSIS

  use HTGT::QC::Which;

  my $full_path = which( 'perl' );

=head1 DESCRIPTION

This module exports the single function, C<which>.  This is identical
to that exported by L<File::Which> only this module throws an
exception if the requested executable is not found, while
L<File::Which> returns undef.

=head1 SEE ALSO

L<File::Which>.

=head1 AUTHOR

Ray Miller E<lt>rm7@sanger.ac.ukE<gt>.

=cut

