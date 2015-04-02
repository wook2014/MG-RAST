package resources::submission;

use strict;
use warnings;
no warnings('once');

use POSIX qw(strftime);
use Digest::MD5 qw(md5_hex md5_base64);
use Data::Dumper;
use Template;

use Conf;
use parent qw(resources::resource);

# Override parent constructor
sub new {
    my ($class, @args) = @_;

    # Call the constructor of the parent class
    my $self = $class->SUPER::new(@args);
    
    # Add name / attributes
    $self->{name} = "submission";
    return $self;
}

# resource is called without any parameters
# this method must return a description of the resource
sub info {
    my ($self) = @_;
    my $content = {
        'name' => $self->name,
        'url' => $self->cgi->url."/".$self->name,
        'description' => "submission runs input through a series of validation and pre-processing steps, then submits the results to the MG-RAST anaylsis pipeline",
        'type' => 'object',
        'documentation' => $self->cgi->url.'/api.html#'.$self->name,
        'requests' => [
            { 'name'        => "info",
              'request'     => $self->cgi->url."/".$self->name,
              'description' => "Returns description of parameters and attributes.",
              'method'      => "GET",
              'type'        => "synchronous",  
              'attributes'  => "self",
              'parameters'  => {
                  'options'  => {},
                  'required' => {},
                  'body'     => {}
              }
            },
            { 'name'        => "reserve",
              'request'     => $self->cgi->url."/".$self->name."/reserve",
              'description' => "reserve new submission ID",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "status",
              'request'     => $self->cgi->url."/".$self->name."/status/{UUID}",
              'description' => "get status of submission from ID",
              'method'      => "GET",
              'type'        => "synchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for submission" ] },
                  'body'     => {}
              }
            },
            { 'name'        => "submit",
              'request'     => $self->cgi->url."/".$self->name."/submit/{UUID}",
              'description' => "start submission for ID",
              'method'      => "POST",
              'type'        => "asynchronous",
              'attributes'  => {
                  'id'         => [ 'string', "RFC 4122 UUID for submission" ],
                  'user'       => [ 'string', "user id" ],
                  'status'     => [ 'string', "status message" ],
                  'timestamp'  => [ 'string', "timestamp for return of this query" ]
              },
              'parameters'  => {
                  'options'  => {},
                  'required' => { "auth" => [ "string", "unique string of text generated by MG-RAST for your account" ],
                                  "uuid" => [ "string", "RFC 4122 UUID for submission" ] },
                  'body'     => {
                      # inbox action options
                      "project_name"   => [ "string", "unique MG-RAST project name" ],
                      "project_id"     => [ "string", "unique MG-RAST project identifier" ],
                      "metadata_file"  => [ "string", "RFC 4122 UUID for metadata file" ],
                      "seq_files"      => [ "list", ["string", "RFC 4122 UUID for sequence file"] ],
                      "multiplex_file" => [ "string", "RFC 4122 UUID for file to demultiplex" ],
                      "barcode_file"   => [ "string", "RFC 4122 UUID for barcode file" ],
                      "pair_file_1"    => [ "string", "RFC 4122 UUID for pair 1 file" ],
                      "pair_file_2"    => [ "string", "RFC 4122 UUID for pair 2 file" ],
                      "index_file"     => [ "string", "RFC 4122 UUID for optional index (barcode) file" ],
                      "barcode_count"  => [ "int", "number of unique barcodes in index_file" ],
                      "retain"         => [ "boolean", "If true retain non-overlapping sequences, default is false" ],
                      # pipeline flags
                      "assembled"    => [ "boolean", "If true sequences are assembeled, default is false" ],
                      "filter_ln"    => [ "boolean", "If true run sequence length filtering, default is true" ],
                      "filter_ambig" => [ "boolean", "If true run sequence ambiguous bp filtering, default is true" ],
                      "dynamic_trim" => [ "boolean", "If true run qual score dynamic trimmer, default is true" ],
                      "dereplicate"  => [ "boolean", "If true run dereplication, default is true" ],
                      "bowtie"       => [ "boolean", "If true run bowtie screening, default is true" ],
                      # pipeline options
                      "max_ambig" => [ "int", "maximum ambiguous bps to allow through per sequence, default is 5" ],
                      "max_lqb"   => [ "int", "maximum number of low-quality bases per read, default is 5" ],
                      "min_qual"  => [ "int", "quality threshold for low-quality bases, default is 15" ],
                      "filter_ln_mult" => [ "float", "sequence length filtering multiplier, default is 2.0" ],
                      "screen_indexes" => [ "cv", ["h_sapiens", "Homo sapiens (default)"],
                                                  ["a_thaliana", "Arabidopsis thaliana"],
                                                  ["b_taurus", "Bos taurus"],
                                                  ["d_melanogaster", ""],
                                                  ["e_coli", "Drosophila melanogaster"],
                                                  ["m_musculus", "Mus musculus"],
                                                  ["r_norvegicus", "Rattus norvegicus"],
                                                  ["s_scrofa", "Sus scrofa"] ],
                      "priority" => [ "cv", ["never", "Data will stay private (default)"]
                                            ["immediately", "Data will be publicly accessible immediately after processing completion"],
                                            ["3months", "Data will be publicly accessible after 3 months"],
                                            ["6months", "Data will be publicly accessible after 6 months"],
                                            ["date", "Data will be publicly accessible eventually"] ]
                  }
              }
            }
        ]
    };
    $self->return_data($content);
}

# Override parent request function
sub request {
    my ($self) = @_;
    
    # determine sub-module to use
    if (scalar(@{$self->rest}) == 0) {
        $self->info();
    } elsif (exists $self->{job_actions}{ $self->rest->[0] }) {
        $self->job_action($self->rest->[0]);
    } elsif (($self->rest->[0] eq 'kb2mg') || ($self->rest->[0] eq 'mg2kb')) {
        $self->id_lookup($self->rest->[0]);
    } else {
        $self->info();
    }
}

# Override parent request function
sub request {
    my ($self) = @_;
    # must have auth
    if ($self->user) {
        if (scalar(@{$self->rest}) == 0) {
            $self->info();
        } elsif ($self->rest->[0] eq 'reserve') {
            $self->reserve();
        } elsif (scalar(@{$self->rest}) == 2) {
            if (($self->rest->[0] eq 'status') && ($self->method eq 'GET')) {
                $self->status($self->rest->[1]);
            } elsif (($self->rest->[0] eq 'submit') && ($self->method eq 'POST')) {
                $self->submit($self->rest->[1]);
            }
        }
    }
    $self->info();
}

sub reserve {
    my ($self) = @_;
    $self->return_data({
        id         => $self->uuidv4(),
        user       => 'mgu'.$self->user->_id,
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub status {
    my ($self, $uuid) = @_;
    # magic to get status
    $self->return_data({
        id         => $uuid,
        user       => 'mgu'.$self->user->_id,
        status     => "",
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

sub submit {
    my ($self, $uuid) = @_;
    
    # inbox action options
    $project_name   = $self->cgi->param('project_name') || "";
    $project_id     = $self->cgi->param('project_id') || "";
    $metadata_file  = $self->cgi->param('metadata_file') || "";
    @seq_files      = $self->cgi->param('seq_files') || ();
    $multiplex_file = $self->cgi->param('multiplex_file') || "";
    $barcode_file   = $self->cgi->param('barcode_file') || "";
    $pair_file_1    = $self->cgi->param('pair_file_1') || "";
    $pair_file_2    = $self->cgi->param('pair_file_2') || "";
    $index_file     = $self->cgi->param('index_file') || "";
    $barcode_count  = $self->cgi->param('barcode_count') || 0;
    $retain         = $self->cgi->param('retain') || "";
    # pipeline parameters
    my $pipeline_params = {
        # flags
        assembled     => $self->cgi->param('assembled') ? 1 : 0,
        filter_ln     => $self->cgi->param('filter_ln') ? 1 : 0,
        filter_ambig  => $self->cgi->param('filter_ambig') ? 1 : 0,
        dynamic_trim  => $self->cgi->param('dynamic_trim') ? 1 : 0,
        dereplicate   => $self->cgi->param('dereplicate') ? 1 : 0,
        bowtie        => $self->cgi->param('bowtie') ? 1 : 0,
        # options
        priority  => $self->cgi->param('priority') || "never",
        max_ambig => $self->cgi->param('max_ambig') || 5,
        max_lqb   => $self->cgi->param('max_lqb') || 5,
        min_qual  => $self->cgi->param('min_qual') || 15,
        filter_ln_mult => $self->cgi->param('filter_ln_mult') || 2.0,
        screen_indexes => $self->cgi->param('screen_indexes') || "h_sapiens"
    };
    
    my $project_obj = "";
    my $metadata_obj = undef;
    my $md_json_node = undef;
    my $response = {
        id         => $uuid,
        user       => 'mgu'.$self->user->_id,
        status     => "",
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    };
    
    # process metadata
    if ($metadata_file) {
        # validate / extract barcodes if exist
        my ($is_valid, $mdata, $log, $bar_id, $bar_count, $json_node) = $self->metadata_validation($metadata_file, 1, 1, $self->token, $self->user_auth, $uuid);
        unless ($is_valid) {
            $response->{status} = "invalid metadata";
            $response->{error} = ($mdata && (@$mdata > 0)) ? $mdata : $log;
            $self->return_data($response);
        }
        $project_name = $data->{data}{project_name}{value};
        $metadata_obj = $mdata;
        $md_json_node = $json_node;
        # use extracted barcodes if mutiplex file
        if ($bar_id && ($bar_count > 1) && $multiplex_file && (! $barcode_file)) {
            $barcode_file = $bar_id;
        }
    }
    
    # check combinations
    if (($pair_file_1 && (! $pair_file_2)) || ($pair_file_2 && (! $pair_file_1))) {
        $self->return_data( {"ERROR" => "Must include pair_file_1 and pair_file_2 together to merge pairs"}, 400 );
    } elsif (($multiplex_file && (! $barcode_file)) || ($barcode_file && (! $multiplex_file))) {
        $self->return_data( {"ERROR" => "Must include multiplex_file and barcode_file together to demultiplex"}, 400 );
    } elsif (! ($pair_file_1 || $multiplex_file || (@seq_files > 0))) {
        $self->return_data( {"ERROR" => "No sequence files provided"}, 400 );
    }
    
    # get project if exists from name or id
    if ($project_id) {
        my (undef, $pid) = $project_id =~ /^(mgp)?(\d+)$/;
        if (! $pid) {
            $self->return_data( {"ERROR" => "invalid project id format: ".$project_id}, 400 );
        }
        $project_id = $pid;
    }
    my $pquery = $project_name ? {name => $project_name} : ($project_id ? {id => $project_id} : undef);
    if ($pquery) {
        my $projects = $jobdbm->Project->get_objects($pquery);
        if (scalar(@$projects) && $user->has_right(undef, 'edit', 'project', $projects->[0]->id)) {
            $project_obj = $projects->[0];
            unless ($project_name) {
                $project_name = $project_obj->{name};
            }
        }
    }
    # make project if no metadata
    if ((! $metadata_obj) && (! $project_obj) && $project_name) {
        $project_obj = $jobdbm->Project->create_project($user, $project_name);
    }
    # verify it worked
    unless ($project_obj) {
        $self->return_data( {"ERROR" => "Missing project information, must have one of metadata_file, project_id, or project_name"}, 400 );
    }
    
    # figure out pre-pipeline workflow
    my @submit = ();
    my $tasks = [];
    if ($pair_file_1 && $pair_file_2 && $index_file) {
        $self->add_submission($pair_file_1, $uuid, $self->token, $self->user_auth);
        $self->add_submission($pair_file_2, $uuid, $self->token, $self->user_auth);
        $self->add_submission($index_file, $uuid, $self->token, $self->user_auth);
        my $outprefix = $self->uuidv4();
        # need stats on input files, each one can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p2_tid = scalar(@$tasks);
        my $p1_fname = (keys %{$tasks->[$p2_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $idx_tid = scalar(@$tasks);
        my $p2_fname = (keys %{$tasks->[$idx_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($idx_tid, -1, $index_file, undef, $self->token, $self->user_auth);
        my $pj_tid = scalar(@$tasks);
        my $idx_fname = (keys %{$tasks->[$pj_tid-1]->{outputs}})[0];
        # pair join - this is 2 tasks, dependent on previous tasks        
        # $taskid, $depend_p1, $depend_p2, $depend_idx, $pair1, $pair2, $index, $bc_num, $outprefix, $retain, $auth, $authPrefix
        push @$tasks, $self->build_pair_join_task($pj_tid, $p2_tid-1, $idx_tid-1, $pj_tid-1, $p1_fname, $p2_fname, $idx_fname, $barcode_count, $outprefix, $retain, $self->token, $self->user_auth);
        # create barcode file - 1 task
        my $bc_tid = scalar(@$tasks);
        push @$tasks, $self->build_index_bc_task($bc_tid, $pj_tid-1, $index, $outprefix, $self->token, $self->user_auth);
        # demultiplex it - # of tasks = barcode_count + 1 (start at task 3)
        unless ($barcode_count && ($barcode_count > 0)) {
            $self->return_data( {"ERROR" => "barcode_count is required for mate-pair demultiplexing, must be greater than 1"}, 400 );
        }
        my $dm_tid = scalar(@$tasks);
        # $taskid, $depend_seq, $depend_bc, $seq, $barcode, $bc_num, $auth, $authPrefix
        @submit = $self->build_demultiplex_task($dm_tid, $bc_tid-1, $dm_tid-1, $outprefix.".fastq", $outprefix.".barcodes", $barcode_count, $self->token, $self->user_auth);
        push @$tasks, @submit;
    } elsif ($pair_file_1 && $pair_file_2) {
        $self->add_submission($pair_file_1, $uuid, $self->token, $self->user_auth);
        $self->add_submission($pair_file_2, $uuid, $self->token, $self->user_auth);
        my $outprefix = $self->uuidv4();
        # need stats on input files, each one can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $pair_file_1, undef, $self->token, $self->user_auth);
        my $p2_tid = scalar(@$tasks);
        my $p1_fname = (keys %{$tasks->[$p2_tid-1]->{outputs}})[0];
        push @$tasks, $self->build_seq_stat_task($p2_tid, -1, $pair_file_2, undef, $self->token, $self->user_auth);
        my $pj_tid = scalar(@$tasks);
        my $p2_fname = (keys %{$tasks->[$pj_tid-1]->{outputs}})[0];
        # pair join - this is 2 tasks, dependent on previous tasks
        # $taskid, $depend_p1, $depend_p2, $depend_idx, $pair1, $pair2, $index, $bc_num, $outprefix, $retain, $auth, $authPrefix
        @submit = $self->build_pair_join_task($pj_tid, $p2_tid-1, $pj_tid-1, undef, $p1_fname, $p2_fname, undef, undef, $outprefix, $retain, $self->token, $self->user_auth);
        push @$tasks, @submit;
    } elsif ($multiplex_file && $barcode_file) {
        $self->add_submission($multiplex_file, $uuid, $self->token, $self->user_auth);
        $self->add_submission($barcode_file, $uuid, $self->token, $self->user_auth);
        # need stats on input file, can be 1 or 2 tasks
        push @$tasks, $self->build_seq_stat_task(0, -1, $multiplex_file, undef, $self->token, $self->user_auth);
        my $dm_tid = scalar(@$tasks);
        my $mult_fname = (keys %{$tasks->[$dm_tid-1]->{outputs}})[0];
        # just demultiplex - # of tasks = barcode_count + 1 (start at task 0)
        # $taskid, $depend_seq, $depend_bc, $seq, $barcode, $bc_num, $auth, $authPrefix
        @submit = $self->build_demultiplex_task($dm_tid, $dm_tid-1, -1, $mult_fname, $barcode_file, 0, $self->token, $self->user_auth);
        push @$tasks, @submit
    } elsif (scalar(@seq_files) > 0) {
        # one or more sequence files, no transformations
        my $taskid = 0;
        foreach my $seq (@seq_files) {
            $self->add_submission($seq, $uuid, $self->token, $self->user_auth);
            my ($task1, $task2) = $self->build_seq_stat_task($taskid, -1, $seq, undef, $self->token, $self->user_auth);
            push @$tasks, $task1;
            $taskid += 1;
            # this is a sff file
            if ($task2) {
                push @submit, $task2;
                push @$tasks, $task2;
                $taskid += 1;
            } else {
                push @submit, $task1;
            }
        }
    } else {
        $self->return_data( {"ERROR" => "Invalid pre-processing option combination, no suitable sequence files found"}, 400 );
    }
    
    # extract sequence files to submit
    my $seq_files = [];
    my $seq_tids = [];
    foreach my $s (@submit) {
        if (exists($s->{userattr}{data_type}) && ($s->{userattr}{data_type} eq "sequence")) {
            foreach my $o (keys %{$s->{outputs}}) {
                push @$seq_files, $o;
            }
            push @$seq_tids, $s->{taskid};
        }
    }
    
    # post parameters to shock
    my $param_str = $self->json->encode({files => $seq_files, parameters => $pipeline_params, submission => $uuid});
    my $param_file = "submission_parameters.json";
    my $param_attr = {
        type  => 'inbox',
        id    => 'mgu'.$self->user->_id,
        user  => $self->user->login,
        email => $self->user->email,
        submission => $uuid,
        stats_info => {
            type      => 'ASCII text',
            suffix    => 'json',
            file_type => 'json',
            file_name => $param_file,
            file_size => length($param_str),
            checksum  => md5_hex($param_str)
        }
    };
    my $param_node = $self->set_shock_node($param_file, $param_str, $param_attr, $self->token, 1, $self->user_auth);
    $self->edit_shock_acl($param_node->{id}, $self->token, 'mgrast', 'put', 'all', $self->user_auth);
    
    # add submission task
    my $staskid = scalar(@$tasks);
    my $submit_task = $self->empty_awe_task();
    $submit_task->{cmd}{description} = 'mg submit '.scalar(@$seq_files);
    $submit_task->{cmd}{name} = "awe_submit_to_mgrast.pl";
    $submit_task->{cmd}{args} = '-input @'.$param_file;
    $submit_task->{cmd}{environ}{private} = {"USER_AUTH" => $self->token, "MGRAST_API" => $Conf::cgi_url};
    $submit_task->{taskid} = "$staskid";
    $submit_task->{dependsOn} = $seq_tids;
    $submit_task->{inputs}{$param_file} = {host => $Conf::shock_url, node => $param_node->{id}};
    # metadata or project
    if ($metadata_obj && $md_json_node) {
        $submit_task->{cmd}{args} .= ' -metadata @'.$md_json_node->{file}{name};
        $submit_task->{inputs}{$md_json_node->{file}{name}} = {host => $Conf::shock_url, node => $md_json_node->{id}};
    } elsif ($project_obj) {
        $submit_task->{cmd}{args} .= ' -project mgp'.$project_obj->{id};
    } else {
        $self->return_data( {"ERROR" => "Missing project information, must have one of metadata_file, project_id, or project_name"}, 400 );
    }
    push @$tasks, $submit_task;
    
    # build workflow
    my $info = {
        shock_url     => $Conf::shock_url,
        job_name      => 'mgu'.$self->user->_id.'_submission',
        user_id       => 'mgu'.$self->user->_id,
        user_name     => $self->user->login,
        user_email    => $self->user->email,
        clientgroups  => $Conf::mgrast_inbox_clientgroups,
        submission_id => $uuid,
        task_list     => $self->json->encode($tasks)
    };
    my $job = $self->submit_awe_template($info, $Conf::mgrast_submission_workflow, $self->token, $self->user_auth);
    
    $self->return_data({
        id         => $uuid,
        user       => 'mgu'.$self->user->_id,
        status     => "",
        timestamp  => strftime("%Y-%m-%dT%H:%M:%S", gmtime)
    });
}

1;
