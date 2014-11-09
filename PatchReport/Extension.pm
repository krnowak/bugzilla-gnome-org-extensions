package Bugzilla::Extension::PatchReport;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::PatchReport::Util;

our $VERSION = '0.01';

sub page_before_template {
    my ($self, $args) = @_;

    page(%{ $args });
}

sub gnome_deps {
    ('GnomeAttachmentStatus');
}

sub enabled {
    1;
}

__PACKAGE__->NAME;
