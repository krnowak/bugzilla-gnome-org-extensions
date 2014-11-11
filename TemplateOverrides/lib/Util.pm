# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TemplateOverrides::Util;

use 5.10.1;
use strict;
use warnings;
use parent qw(Exporter);
use Array::Utils qw(array_minus intersect);
use IO::Dir;
use File::Spec;

our @EXPORT = qw(
    check_overridden_templates
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::TemplateOverrides::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub _get_templates {
    my (@initial_paths) = @_;
    my @paths = map {[$_, undef]} @initial_paths;
    my @tmpls = ();

    while (@paths) {
        my $path_pair = shift(@paths);
        my $initial = $path_pair->[0];
        my $rest = $path_pair->[1];
        my $path = $initial;

        if (defined($rest)) {
            $path = File::Spec->catdir($initial, $rest);
        }

        my $dir = IO::Dir->new($path);

        next unless defined($dir);
        while (defined(my $entry = $dir->read())) {
            next if $entry =~ /^\.{1,2}$/;

            my $rest_entry = $entry;

            if (defined($rest)) {
                $rest_entry = File::Spec->catdir($rest, $entry);
            }

            my $complete_path = File::Spec->catdir($initial, $rest_entry);

            if (-d $complete_path) {
                push(@paths, [$initial, $rest_entry]);
                next;
            }
            if ($entry =~ /\.tmpl$/) {
                push(@tmpls, $rest_entry);
                next;
            }
        }
    }

    @tmpls;
}

sub _check_overrides {
    my ($extension_paths, $default_paths, $digests) = @_;
    my @overridden = _get_templates(@{$extension_paths});
    my @default = _get_templates(@{$default_paths});
    my @common = intersect(@default, @overridden);
    my @not_overrides = array_minus(@overridden, @common);

    if (@not_overrides) {
        die 'Following templates are not overriding ' .
            'anything: ' . join(', ', @not_overrides);
    }

    my @digested_files = keys(%{$digests});
    my @not_digested = array_minus(@overridden, @digested_files);

    if (@not_digested) {
        die 'Following overrides are missing their digests: ' .
            join(', ', @not_digested);
    }

    my @digested_not_overrides = array_minus(@digested_files, @overridden);

    if (@digested_not_overrides) {
        die 'Following files have digests, but no overrides for them exist: ' .
            join(', ', @digested_not_overrides);
    }
}

sub check_overridden_templates {
    my ($silent) = @_;
    my %digests = (
        'attachment/edit.html.tmpl' => '426ceeb820cefad35cbbf10ab053c1fc9f53fa71a63dd455418bff3221a46a0e',
        'attachment/list.html.tmpl' => 'b0c5edd84b8cc31666d0d0b4bf36cdb981ee322995dad891cf05f0f40b2d0392',
        'bug/comments.html.tmpl' => 'd68e98b67eac9cd74ec7b0b663734f7a14953788864135be076a8cb03d648f09',
        'global/user.html.tmpl' => 'ca16e2a988436109612b7b249e536f49669d4c5a9161911e3c14906a5f6d041d',
        'global/choose-classification.html.tmpl' => 'da8b876b1a79fb40b5ec2e46e6706b63aa0d6ec15a6a41c80ebc1ad889e6e0d4',
        'global/choose-product.html.tmpl' => 'ab607993022411e13f6cfa51d3c6c32e9309b4c54640347e67742baee8a5e941',
        'global/common-links.html.tmpl' => 'bd97d3329db516532e773b6446da863e7d5eb141e057f1a121d1d1a4417e4f06',
    );

    print "Checking overridden templates...\n" unless $silent;
    return unless keys(%digests);
    # template_include_path is from Bugzilla::Install::Util package.
    my @template_paths = map {File::Spec->canonpath($_)} @{Bugzilla::Install::Util::template_include_path()};
    my @extension_paths = grep {/^extensions\/TemplateOverrides\//} @template_paths;
    my @default_paths = grep {!/^extensions\//} @template_paths;

    _check_overrides(\@extension_paths, \@default_paths, \%digests);
    for my $file (sort keys (%digests))
    {
        my $complete_path = undef;

        for my $path (@default_paths)
        {
            my $potential_path = File::Spec->catfile($path, $file);

            next unless (-r $potential_path);
            $complete_path = $potential_path;
            last;
        }
        unless ($complete_path)
        {
            die "Original template for $file not found - should not happen";
        }

        my $sha = Digest::SHA->new(256);
        $sha->addfile($complete_path);
        my $digest = $sha->hexdigest();
        if ($digest ne $digests{$file})
        {
            die "Original $file (at $complete_path) has changed " .
            'since last checksetup. Please check if the changes ' .
            'should be backported to overridden templates and ' .
            'update the digest in %digests variable with ' .
            $digest;
        }
    }
}

1;
