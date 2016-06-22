package HTGT::QC::CLI;

use Moose;
use namespace::autoclean;

extends 'MooseX::App::Cmd';

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
