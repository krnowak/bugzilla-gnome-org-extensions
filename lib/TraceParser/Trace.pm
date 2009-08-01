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

package TraceParser::Trace;
use strict;
use base qw(Bugzilla::Object);

use Bugzilla::Bug;
use Bugzilla::Error;
use Bugzilla::Util;

use Parse::StackTrace;
use Digest::MD5 qw(md5_base64);

###############################
####    Initialization     ####
###############################

use constant DB_COLUMNS => qw(
    has_symbols
    id
    full_hash
    short_hash
    thetext
    type
    quality
);

use constant DB_TABLE => 'trace';

use constant VALIDATORS => {
    has_symbols => \&Bugzilla::Object::check_boolean,
    full_hash   => \&_check_hash,
    short_hash  => \&_check_hash,
    short_stack => \&_check_short_stack,
    thetext     => \&_check_thetext,
    type        => \&_check_type,
    quality     => \&_check_quality,
};

use constant REQUIRED_CREATE_FIELDS => qw(type full_hash short_hash);

# This is how long a Base64 MD5 Hash is.
use constant HASH_SIZE => 22;

use constant TRACE_TYPES => ['GDB', 'Python'];

use constant IGNORE_FUNCTIONS => qw(
   __kernel_vsyscall
   raise
   abort
   ??
);

################
# Constructors #
################

# Returns a hash suitable for passing to create(), or undef if there is no
# trace in the comment.
sub parse_from_text {
    my ($class, $text) = @_;
    my $trace = Parse::StackTrace->parse(types => TRACE_TYPES, 
                                         text => $text);
    return undef if !$trace;

    my @all_functions;
    my $quality = 0;
    my $has_symbols = 1;
    my $crash_thread = $trace->thread_with_crash || $trace->threads->[0];
    foreach my $frame (@{ $crash_thread->frames }) {
        foreach my $item (qw(args number file line code)) {
            $quality++ if defined $frame->$item && $frame->$item ne '';
        }
        my $function = $frame->function;
        if (!grep($_ eq $function, IGNORE_FUNCTIONS)) {
            push(@all_functions, $frame->function);
        }
        if ($function eq '??') {
            $has_symbols = 0;
        }
        else {
            $quality++;
        }
    }

    my $max_short_stack = $#all_functions > 4 ? 4 : $#all_functions;
    my @short_stack = @all_functions[0..$max_short_stack];
    my $stack_hash = md5_base64(join(',', @all_functions));
    my $short_hash = md5_base64(join(',', @short_stack));
    my $trace_text = $trace->text;

    return {
        has_symbols => $has_symbols,
        stack_hash  => $stack_hash,
        short_hash  => $short_hash,
        short_stack => join(', ', @short_stack),
        trace_hash  => md5_base64($text),
        trace_text  => $trace_text,
        type        => ref($trace),
        quality     => $quality,
    };
}

###############################
####      Accessors      ######
###############################

sub has_symbols { return $_[0]->{has_symbols}; }
sub full_hash   { return $_[0]->{full_hash};   }
sub short_hash  { return $_[0]->{short_hash};  }
sub short_stack { return $_[0]->{short_stack}; }
sub trace_text  { return $_[0]->{trace_text};  }
sub type        { return $_[0]->{type};        }
sub quality     { return $_[0]->{quality};     }

sub stacktrace_object {
    my $self = shift;
    my $type = $self->type;
    eval("use $type") || die $@;
    $self->{stacktrace_object} ||= $type->parse({ text => $self->trace_text });
    return $self->{stacktrace_object};
}

###############################
###       Validators        ###
###############################

sub _check_hash {
    my ($self, $hash) = @_;
    $hash = trim($hash);
    ThrowCodeError('traceparser_no_hash') if !$hash;
    length($hash) == HASH_SIZE
        or ThrowCodeError('traceparser_bad_hash', { hash => $hash });
    return $hash;
}

sub _check_short_stack { return trim($_[1]) || '' }

sub _check_thetext {
    my ($invocant, $text) = @_;
    if (!$text or $text =~ /^\s+$/s) {
        my $class = ref($invocant) || $invocant;
        ThrowCodeError('param_required', { function => "${class}::create",
                                           param    => 'thetext' });
    }
    return $text;
}

sub _check_type {
    my ($invocant, $type) = @_;
    $type = trim($type);
    if (!$type) {
        my $class = ref($invocant) || $invocant;
        ThrowCodeError('param_required', { function => "${class}::create",
                                           param    => 'type' });
    }
    $type =~ /^Parse::StackTrace::Type/
      or ThrowCodeError('traceparser_bad_type', { type => $type });
    return $type;
}

sub _check_quality { return int($_[1]); }

1;
