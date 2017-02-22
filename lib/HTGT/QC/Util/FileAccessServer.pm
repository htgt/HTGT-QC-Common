package HTGT::QC::Util::FileAccessServer;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $HTGT::QC::Util::FileAccessServer::VERSION = '0.050';
}
## use critic


use Moose;
use WWW::JSON;
use LWP::UserAgent;

with 'MooseX::Log::Log4perl';

# This is a helper module for accessing files in directories
# which are not available to the machine that the webapp is
# running on via a rest-fs server.
# Mainly for LIMS2 QC


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

sub fileserver_get_json{
    my ($self, $path, $params) = @_;

    my $get = $self->get_json($path, $params);

    if($get->success){
        return $get->res;
    }
    else{
        die "Could not get JSON from $path: ".$get->error;
    }

    return;
};

sub get_file_content{
    my ($self, $path) = @_;
    my $full_path = $self->file_api_url()."/".$path;
    my $response = $self->user_agent->get($full_path);

    unless($response->is_success){
        die "Could not get file $path: ".$response->status_line;
    }

    return $response->content;
}

sub post_file_content{
	my ($self, $path, $content) = @_;

    my $post_url = $self->file_api_url.$path;
    $self->log->debug("posting file content to $post_url");

    return $self->user_agent->post($post_url, Content_Type => 'text/plain', Content => $content );
}

sub make_dir{
    my ($self, $path) = @_;

    my $post_url = $self->file_api_url.$path."/";
    $self->log->debug("posting directory to $post_url");

    my $response = $self->user_agent->post($post_url);
    unless($response->is_success){
        die "Could not create directory $path: ".$response->status_line;
    }

    return $response->content;
}

1;