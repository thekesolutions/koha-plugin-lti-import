package Koha::Plugin::Com::ThekeSolutions::LTIImport;

# This plugin is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Charset;
use C4::Context;
use C4::Auth;
use C4::Output;
use C4::Biblio;
use C4::ImportBatch;
use C4::Matcher;
use Koha::UploadedFiles;
use C4::BackgroundJob;
use C4::MarcModificationTemplates;
use Koha::Biblio::Metadatas;
use Koha::Biblios;
use Koha::Plugins;

use Data::Printer;
use MARC::Record;

## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'LTI MARC import',
    author          => 'Tomas Cohen Arazi',
    date_authored   => '2018-03-14',
    date_updated    => "2018-03-14",
    minimum_version => '17.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 
        'This plugin implements a way to define rules for the process'
      . 'of overlaying MARC record on the DB.'
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{cgi};

    unless ( $cgi->param( 'stage_files' ) ) {
        $self->tool_step1();
    }
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    ## TODO: Error handling on the configuration format

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            rules => $self->retrieve_data('rules')
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        my $rules = $cgi->param('rules');
        $self->store_data(
            {
                rules => $rules
            }
        );
        $self->go_home();
    }
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $file_id                    = $cgi->param('uploadedfileid');
    my $record_type                = $cgi->param('record_type');
    my $runinbackground            = $cgi->param('runinbackground');
    my $completedJobID             = $cgi->param('completedJobID');
    my $matcher_id                 = $cgi->param('matcher');
    my $overlay_action             = $cgi->param('overlay_action');
    my $nomatch_action             = $cgi->param('nomatch_action');
    my $parse_items                = $cgi->param('parse_items');
    my $item_action                = $cgi->param('item_action');
    my $comments                   = $cgi->param('comments');
    my $encoding                   = $cgi->param('encoding') || 'UTF-8';
    my $format                     = $cgi->param('format') || 'ISO2709';
    my $marc_modification_template = $cgi->param('marc_modification_template_id');

    my $template = $self->get_template( { file => 'tool-step1.tt' } );

    $template->param(
        uploadmarc  => $file_id,
        record_type => $record_type,
    );

    my %cookies   = fetch CGI::Cookie;
    my $sessionID = $cookies{'CGISESSID'}->value;

    if ($completedJobID) {
        my $job = C4::BackgroundJob->fetch( $sessionID, $completedJobID );
        my $results = $job->results();
        $template->param( map { $_ => $results->{$_} } keys %{$results} );
    }
    elsif ($file_id) {
        my $upload   = Koha::UploadedFiles->find($file_id);
        my $file     = $upload->full_path;
        my $filename = $upload->filename;

        my ( $errors, $marcrecords );
        if ( $format eq 'MARCXML' ) {
            ( $errors, $marcrecords ) = $self->RecordsFromMARCXMLFile( $file, $encoding );
        }
        elsif ( $format eq 'ISO2709' ) {
            ( $errors, $marcrecords )
                = $self->RecordsFromISO2709File( $file, $record_type, $encoding );
        }
        else {    # plugin based
            $errors = [];
            $marcrecords = C4::ImportBatch::RecordsFromMarcPlugin( $file, $format, $encoding );
        }
        warn "$filename: " . ( join ',', @$errors ) if @$errors;

        # no need to exit if we have no records (or only errors) here
        # BatchStageMarcRecords can handle that

        my $job = undef;
        my $dbh;
        if ($runinbackground) {
            my $job_size = scalar(@$marcrecords);

            # if we're matching, job size is doubled
            $job_size *= 2 if ( $matcher_id ne "" );
            $job = C4::BackgroundJob->new( $sessionID, $filename,
                '/cgi-bin/koha/tools/stage-marc-import.pl', $job_size );
            my $jobID = $job->id();

            # fork off
            if ( my $pid = fork ) {

                # parent
                # return job ID as JSON
                my $reply = CGI->new("");
                print $reply->header( -type => 'text/html' );
                print '{"jobID":"' . $jobID . '"}';
                exit 0;
            }
            elsif ( defined $pid ) {

                # child
                # close STDOUT to signal to Apache that
                # we're now running in the background
                close STDOUT;

                # close STDERR; # there is no good reason to close STDERR
            }
            else {
                # fork failed, so exit immediately
                warn
                    "fork failed while attempting to run tools/stage-marc-import.pl as a background job: $!";
                exit 0;
            }

            # if we get here, we're a child that has detached
            # itself from Apache

        }

        # New handle, as we're a child.
        $dbh = C4::Context->dbh( { new => 1 } );
        $dbh->{AutoCommit} = 0;

        # FIXME branch code
        my ( $batch_id, $num_valid, $num_items, @import_errors )
            = BatchStageMarcRecords( $record_type, $encoding, $marcrecords, $filename,
            $marc_modification_template, $comments, '',
            $parse_items, 0, 50, staging_progress_callback( $job, $dbh ) );

        my $num_with_matches = 0;
        my $checked_matches  = 0;
        my $matcher_failed   = 0;
        my $matcher_code     = "";
        if ( $matcher_id ne "" ) {
            my $matcher = C4::Matcher->fetch($matcher_id);
            if ( defined $matcher ) {
                $checked_matches  = 1;
                $matcher_code     = $matcher->code();
                $num_with_matches = BatchFindDuplicates( $batch_id, $matcher, 10, 50,
                    matching_progress_callback( $job, $dbh ) );
                SetImportBatchMatcher( $batch_id, $matcher_id );
                SetImportBatchOverlayAction( $batch_id, $overlay_action );
                SetImportBatchNoMatchAction( $batch_id, $nomatch_action );
                SetImportBatchItemAction( $batch_id, $item_action );
                $dbh->commit();
            }
            else {
                $matcher_failed = 1;
            }
        }
        else {
            $dbh->commit();
        }

        my $results = {
            staged          => $num_valid,
            matched         => $num_with_matches,
            num_items       => $num_items,
            import_errors   => scalar(@import_errors),
            total           => $num_valid + scalar(@import_errors),
            checked_matches => $checked_matches,
            matcher_failed  => $matcher_failed,
            matcher_code    => $matcher_code,
            import_batch_id => $batch_id
        };

        if ($runinbackground) {
            $job->finish($results);
            exit 0;
        }
        else {
            $template->param(
                staged          => $num_valid,
                matched         => $num_with_matches,
                num_items       => $num_items,
                import_errors   => scalar(@import_errors),
                total           => $num_valid + scalar(@import_errors),
                checked_matches => $checked_matches,
                matcher_failed  => $matcher_failed,
                matcher_code    => $matcher_code,
                import_batch_id => $batch_id
            );
        }

    }
    else {
        # initial form
        if ( C4::Context->preference("marcflavour") eq "UNIMARC" ) {
            $template->param( "UNIMARC" => 1 );
        }
        my @matchers = C4::Matcher::GetMatcherList();
        $template->param( available_matchers => \@matchers );

        my @templates = GetModificationTemplates();
        $template->param( MarcModificationTemplatesLoop => \@templates );

        if (   C4::Context->preference('UseKohaPlugins')
            && C4::Context->config('enable_plugins') )
        {

            my @plugins = Koha::Plugins->new()->GetPlugins( { method => 'to_marc', } );
            $template->param( plugins => \@plugins );
        }
    }

    print $cgi->header();
    print $template->output();
}

sub staging_progress_callback {
    my $job = shift;
    return sub {
        my $progress = shift;
        $job->progress($progress);
    }
}

sub matching_progress_callback {
    my $job = shift;
    my $start_progress = $job->progress();
    return sub {
        my $progress = shift;
        $job->progress($start_progress + $progress);
    }
}

sub RecordsFromISO2709File {
    my ($self, $input_file, $record_type, $encoding) = @_;
    my @errors;

    my $marc_type = C4::Context->preference('marcflavour');
    $marc_type .= 'AUTH' if ($marc_type eq 'UNIMARC' && $record_type eq 'auth');

    open IN, "<$input_file" or die "$0: cannot open input file $input_file: $!\n";
    my @marc_records;
    $/ = "\035";
    while (<IN>) {
        s/^\s+//;
        s/\s+$//;
        next unless $_; # skip if record has only whitespace, as might occur
                        # if file includes newlines between each MARC record
        my ($marc_record, $charset_guessed, $char_errors) = C4::Charset::MarcToUTF8Record($_, $marc_type, $encoding);
        $marc_record = $self->_overlay_record($marc_record);
        push @marc_records, $marc_record;
        if ($charset_guessed ne $encoding) {
            push @errors,
                "Unexpected charset $charset_guessed, expecting $encoding";
        }
    }
    close IN;
    return ( \@errors, \@marc_records );
}

=head2 RecordsFromMARCXMLFile

    my ($errors, $records) = C4::ImportBatch::RecordsFromMARCXMLFile($input_file, $encoding);

Creates MARC::Record-objects out of the given MARCXML-file.

@PARAM1, String, absolute path to the ISO2709 file.
@PARAM2, String, should be utf8

Returns two array refs.

=cut

sub RecordsFromMARCXMLFile {
    my ( $self, $filename, $encoding ) = @_;
    my $batch = MARC::File::XML->in( $filename );
    my ( @marcRecords, @errors, $record );
    do {
        eval { $record = $batch->next( $encoding ); };
        if ($@) {
            push @errors, $@;
        }
        $record = $self->_overlay_record($record);
        push @marcRecords, $record if $record;
    } while( $record );
    return (\@errors, \@marcRecords);
}

sub rules {
    my ($self) = @_;
    my $config;

    eval { $config = YAML::Load($self->retrieve_data('rules') . "\n\n"); };

    return $config->{rules}
        if exists $config->{rules};
}

sub _overlay_record {
    my ($self, $record) = @_;

    my $marc_flavour = C4::Context->preference('marcflavour') || 'MARC21';
    # Better read from koha<->marc mappings
    return unless defined $record and ref($record) eq 'MARC::Record';
    my $biblio_id = $record->subfield('999', 'c');
    my $metadata;

    $metadata = Koha::Biblio::Metadatas->search(
        {   biblionumber => $biblio_id,
            format       => 'marcxml',
            marcflavour  => $marc_flavour
        }
        )->next->metadata
        if $biblio_id;


    if ( $metadata )
    {
        # Match!
        my $overlayed_record = eval {
            MARC::Record::new_from_xml( $metadata, "utf8", $marc_flavour );
        };

        # Do your thing based on config
        my $rules = $self->rules;

        if ( $rules ) {
            # Some rules are defined change the original record
            foreach my $rule ( @{ $rules } ) {
                ## TODO: Handle filing indicator option!
                my $fields = $rule->{fields} . '';
                my $filing_indicators_only = ($rule->{filing_indicators_only} eq 'yes') ? 1 : 0;
                # Delete existing fields
                my @fields = $overlayed_record->field( $fields );
                $overlayed_record->delete_fields( @fields );
                # Add new fields
                my @new_fields = $record->field( $fields  );
                $overlayed_record->insert_fields_ordered( @new_fields );
            }
        }

        # Return
        return $overlayed_record;
    }

    return $record;
}

1;
