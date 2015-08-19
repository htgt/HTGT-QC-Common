package HTGT::QC::Util::FileAccessServer;

use Moose;
use WWW::JSON;
use LWP::UserAgent;

with 'MooseX::Log::Log4perl';

# This is a helper module for accessing files in directories
# which are not available to the machine that the webapp is
# running on via a rest-fs server. 
# Mainly for LIMS2 QC and primer generation

# FIXME: need to add some error handling in case server is down
# or requested dir/file path is not found


has file_api_url => (
    is       => 'ro',
    isa      => 'Str',
    required => 1
);

has file_api => (
    is       => 'ro',
    isa      => 'WWW::JSON',
    lazy_build => 1,
    handles => { 'get_json' => 'get' },
);

sub _build_file_api {
    my $self = shift;
    return WWW::JSON->new(
        base_url => $self->file_api_url,
    );
}

has user_agent => (
    is       => 'ro',
    isa      => 'LWP::UserAgent',
    lazy_build => 1,
);

sub _build_user_agent {
    return LWP::UserAgent->new();
}

sub get_file_content{
    my ($self, $path) = @_;
    my $full_path = $self->file_api_url()."/".$path;
    return $self->user_agent->get($full_path)->content;
}

sub post_file_content{
	my ($self, $path, $content) = @_;
    
    my $post_url = $self->file_api_url.$path;
    $self->log->debug("posting file content to $post_url");

    return $self->user_agent->post($post_url, Content_Type => 'text/plain', Content => $content );
}

1;