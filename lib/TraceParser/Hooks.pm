# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by the Initial Developer are Copyright (C) 2009
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package TraceParser::Hooks;
use strict;
use base qw(Exporter);
use Bugzilla::Error;
use Bugzilla::Install::Util qw(indicate_progress);
use TraceParser::Trace;

our @EXPORT = qw(
    install_update_db
    format_comment
    page
);

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    my $has_traces = $dbh->selectrow_array('SELECT 1 FROM trace '
                                           . $dbh->sql_limit('1'));
    return if $has_traces;

    print "Parsing traces from comments...\n";
    my $total = $dbh->selectrow_array('SELECT COUNT(*) FROM longdescs');

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 1;
    }

    my $sth = $dbh->prepare('SELECT comment_id, thetext FROM longdescs 
                           ORDER BY comment_id');
    $sth->execute();
    my $count = 1;
    my @traces;
    while (my ($comment_id, $text) = $sth->fetchrow_array) {
        my $trace = TraceParser::Trace->parse_from_text($text);
        indicate_progress({ current => $count++, total => $total,
                            every => 100 });
        next if !$trace;
        $trace->{comment_id} = $comment_id;
        push(@traces, $trace);
    }

    my $total_traces = scalar(@traces);
    print "Parsed $total_traces traces.\n";

    if ($dbh->isa('Bugzilla::DB::Mysql')) {
        $dbh->{'mysql_use_result'} = 0;
    }

    print "Inserting parsed traces into DB...\n";
    $count = 1;
    $dbh->bz_start_transaction();
    while (my $trace = shift @traces) {
        TraceParser::Trace->create($trace);
        indicate_progress({ current => $count++, total => $total_traces,
                            every => 100 });
    }
    $dbh->bz_commit_transaction();
}

sub format_comment {
    my %params = @_;
    my ($text, $bug, $regexes, $comment) = @params{qw(text bug regexes comment)};
    return if !$comment;
    my ($trace) = @{ TraceParser::Trace->match({ comment_id => $comment->{id} }) };
    return if !$trace;

    # $$text contains the wrapped text, and $comment contains the unwrapped
    # text. To find the trace that we want from the DB, we need to use the
    # unwrapped text. But to find the text that we need to replace, we
    # need to use the wrapped text.
    my $match_text;
    if ($comment->{already_wrapped}) {
        $match_text = $trace->text;
    }
    else {
        my $stacktrace = TraceParser::Trace->stacktrace_from_text($$text);
        $match_text = $stacktrace->text;
    }

    $match_text = quotemeta($match_text);
    my $replacement;
    my $template = Bugzilla->template_inner;
    $template->process('trace/format.html.tmpl', { trace => $trace },
                       \$replacement)
      || ThrowTemplateError($template->error);
    # Make sure that replacements don't contain $1, $2, etc.
    $replacement =~ s{\$}{\\\$};
    push(@$regexes, { match => qr/$match_text/s, replace => $replacement });
}

sub page {
    my %params = @_;
    my ($vars, $page) = @params{qw(vars page_id)};
    return if $page !~ '^trace\.';
    my $trace_id = Bugzilla->cgi->param('trace_id');
    my $trace = TraceParser::Trace->check({ id => $trace_id });
    $trace->bug->check_is_visible;

    if ($trace->stack_hash) {
        my $identical_traces = TraceParser::Trace->match(
            { stack_hash => $trace->stack_hash });
        my $similar_traces = TraceParser::Trace->match(
            { short_hash => $trace->short_hash });
        # Remove identical traces.
        my %identical = map { $_->id => 1 } @$identical_traces;
        @$similar_traces = grep { !$identical{$_->id} } @$similar_traces;
        # Remove this trace from the identical traces.
        @$identical_traces = grep { $_->id != $trace->id } @$identical_traces;
        $vars->{similar_traces} = $similar_traces;
        $vars->{identical_traces} = $identical_traces;
    }

    $vars->{trace} = $trace;
}

1;