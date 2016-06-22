package HTGT::QC::Util::ListFailedRuns;

use Moose;
use YAML::Any;
use List::Util qw( min );
use Path::Class 'dir';
use namespace::autoclean;

with 'MooseX::Log::Log4perl';

has limit => (
    is => 'ro',
    isa => 'Int',
    default => 20
);

has config => (
    is => 'ro',
    isa => 'HTGT::QC::Config',
    required => 1
);

my $OLD_QC_WORK_DIR = '/nfs/team87/data/qc/work';

sub get_failed_run_data{
    my ( $self ) = shift;

    my @failures = reverse sort { $a->{ctime} <=> $b->{ctime} }
        map { { run_id => $_->basename, ctime => $_->stat->ctime } }
            $self->config->runner_basedir->subdir('fail')->children;

    my $max_index = min( scalar @failures, $self->limit ) - 1;

    my @failed_run_data;
    for my $fail ( @failures[0..$max_index] ){
        my $params_file = dir( $OLD_QC_WORK_DIR )->subdir( $fail->{run_id} )->stringify
            . '/params.yaml';
        unless ( -e $params_file ){
            push @failed_run_data, (
                {
                    qc_run_id    => $fail->{run_id},
                    created      => scalar localtime($fail->{ctime})
                }
            );
            next;
        }

        my $params = YAML::Any::LoadFile( $params_file );

        next unless $params->{sequencing_projects}; # Old version of code called this 'sequencing_project',
                                                    # but we aren't interested in these old runs

        push @failed_run_data, (
            {
                qc_run_id    => $fail->{run_id},
                created      => scalar localtime($fail->{ctime}),
                profile      => $params->{profile},
                seq_projects => join('; ', @{$params->{sequencing_projects}}),
                template_plate => $params->{template_plate}
            }
        );
    }

    return \@failed_run_data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
