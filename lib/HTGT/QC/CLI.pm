package HTGT::QC::CLI;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::CLI::VERSION = '0.050';
}
## use critic


use Moose;
use namespace::autoclean;

extends 'MooseX::App::Cmd';

# ABSTRACT: Command line interface to run QC steps

## no critic (ProhibitConstantPragma)

use constant plugin_search_path => [
    map { 'HTGT::QC::Action::' . $_ } qw(
                                            AlignReads
                                            FetchTemplateData
                                            FetchSeqReads
                                            GenerateReport
                                            GenerateRunID
                                            ListFailedRuns
                                            ListReads
                                            ListTraceProjects
                                            Misc
                                            Persist
                                            PostFilter
                                            PreFilter
                                            RunAnalysis
                                            Runner
                                    )
];

__PACKAGE__->meta->make_immutable;

1;

__END__
