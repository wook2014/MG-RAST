package resources::download;

use strict;
use warnings;
no warnings('once');

use Data::Dumper;
use List::MoreUtils qw(any uniq);
use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "download";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self)  = @_;
    my $content = { 'name' => $self->name,
		    'url' => $self->cgi->url."/".$self->name,
		    'description' => "An analysis file from the processing of a metagenome from a specific stage in its analysis",
		    'type' => 'object',
		    'documentation' => $self->cgi->url.'/api.html#'.$self->name,
		    'requests' => [ { 'name'        => "info",
				              'request'     => $self->cgi->url."/".$self->name,
				              'description' => "Returns description of parameters and attributes.",
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => "self",
				              'parameters'  => { 'options'  => {},
							                     'required' => {},
							                     'body'     => {} }
							},
				            { 'name'        => "instance",
				              'request'     => $self->cgi->url."/".$self->name."/{ID}",
				              'description' => "Returns a single sequence file.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3?file=350.1",
      				                             'download fasta file of genecalled protein sequences (from stage 350)' ],
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => { "data" => [ 'file', 'requested analysis file' ] },
				              'parameters'  => { 'options'  => { "file" => [ "string", "file name or identifier" ] },
							                     'required' => { "id" => [ "string", "unique metagenome identifier" ] },
							                     'body'     => {} }
							},
				            { 'name'        => "setlist",
				              'request'     => $self->cgi->url."/".$self->name."/{ID}",
				              'description' => "Returns a list of sets of sequence files for the given id.",
				              'example'     => [ $self->cgi->url."/".$self->name."/mgm4447943.3?stage=650",
        				                         'view all available files from stage 650' ],
				              'method'      => "GET",
				              'type'        => "synchronous",  
				              'attributes'  => { "stage_name" => [ "string", "name of the stage in processing of this file" ],
							                     "stage_id"   => [ "string", "three digit numerical identifier of the stage" ],
							                     "stage_type" => [ "string", "type of the analysis file within a stage, i.e. passed or removed for quality control steps" ],
							                     "file_name"  => [ "string", "name of the analysis file" ],
							                     "file_id"    => [ "string", "unique identifier of file in stage" ],
							                     "id"         => [ "string", "unique metagenome identifier" ],
							                     "url"        => [ "string", "url for retrieving this analysis file" ] },
				             'parameters'  => { 'options'  => { "stage" => [ "string", "stage name or identifier" ] },
							                    'required' => { "id" => [ "string", "unique metagenome identifier" ] },
							                    'body'     => {} }
							} ]
		  };

    $self->return_data($content);
}

# the resource is called with an id parameter
sub instance {
    my ($self) = @_;
  
    # check id format
    my $rest = $self->rest;
    my (undef, $mgid) = $rest->[0] =~ /^(mgm)?(\d+\.\d+)$/;
    if ((! $mgid) && scalar(@$rest)) {
        $self->return_data( {"ERROR" => "invalid id format: ".$rest->[0]}, 400 );
    }
    
    # get job
    my $master = $self->connect_to_datasource();
    my $job = $master->Job->get_objects( {metagenome_id => $mgid, viewable => 1} );
    unless ($job && @$job) {
        $self->return_data( {"ERROR" => "id $mgid does not exists"}, 404 );
    }
    $job = $job->[0];
  
    # check rights
    unless ($job->{public} || ($self->user && ($self->user->has_right(undef, 'view', 'metagenome', $mgid) || $self->user->has_star_right('view', 'metagenome')))) {
        $self->return_data( {"ERROR" => "insufficient permissions to view this data"}, 401 );
    }

    # get data / parameters
    my $setlist = $self->get_download_set($job->{metagenome_id});
    my $stage = $self->cgi->param('stage') || undef;
    my $file  = $self->cgi->param('file') || undef;
    
    # return file
    if ($file) {
        my ($fdir, $fname);
        foreach my $set (@$setlist) {
            if (($set->{file_id} eq $file) || ($set->{file_name} eq $file)) {
                $fname = $set->{file_name};
                $fdir  = ($set->{stage_id} eq "050") ? $job->download_dir : $job->analysis_dir;
            }
        }
        if ($fdir && $fname) {
            $self->return_file($fdir, $fname);
        } else {
            $self->return_data( {"ERROR" => "requested file ($file) is not available"}, 404 );
        }
    }
    
    # return stage list
    if ($stage) {
        my $subsets = [];
        foreach my $set (@$setlist) {
            if (($set->{stage_id} eq $stage) || ($set->{stage_name} eq $stage)) {
                push @$subsets, $set;
            }
        }
        if (@$subsets > 0) {
            $self->return_data($subsets);
        } else {
            $self->return_data( {"ERROR" => "requested stage ($stage) is not available"}, 404 );
        }
    } else {
        $self->return_data($setlist);
    }
}

1;
