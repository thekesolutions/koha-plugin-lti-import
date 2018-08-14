#!/usr/bin/perl

# Copyright 2018 Theke Solutions
#
# This file is part of koha-plugin-lti-import.
#
# koha-plugin-lti-import is free software; you can redistribute it and/or modify
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

# # Add the plugin's dir to the libs path
# use FindBin;
# use lib "$FindBin::Bin/../../../../../";

use C4::Auth qw(checkauth);
use C4::Context;
use lib @{C4::Context->config("pluginsdir")};

use Koha::Plugin::Com::ThekeSolutions::LTIImport;

my $cgi = new CGI;

checkauth( $cgi, 0, { plugins => 'tool' }, 'intranet' );

my $lti = Koha::Plugin::Com::ThekeSolutions::LTIImport->new({ cgi => $cgi });

$lti->tool_step1();

1;
