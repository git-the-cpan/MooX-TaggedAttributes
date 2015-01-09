# --8<--8<--8<--8<--
#
# Copyright (C) 2015 Smithsonian Astrophysical Observatory
#
# This file is part of MooX::TaggedAttributes
#
# MooX::TaggedAttributes is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -->8-->8-->8-->8--

package MooX::TaggedAttributes;

use strict;
use warnings;

our $VERSION = '0.00';

use Carp;

use Moo::Role;

use Class::Method::Modifiers qw[ install_modifier ];

our %TAGSTORE;

my %ARGS = (
    -tags  => [],
);

sub import {

    my ( $class, @args ) = @_;
    my $target = caller;

    Moo::Role->apply_roles_to_package( $target, __PACKAGE__ );

    return unless @args;

    my %args = %ARGS;

    while ( @args ) {

        my $arg = shift @args;

        croak( "unknown argument to ", __PACKAGE__, ": $arg" )
          unless exists $ARGS{$arg};

        $args{$arg} = defined $ARGS{$arg} ? shift @args : 1;
    }

    $args{-tags} = [ $args{-tags} ]
      unless 'ARRAY' eq ref $args{-tags};

    _install_tags( $target, $args{-tags} )
      if @{ $args{-tags} };

    _install_role_import( $target );
}

sub _install_role_import {

    my $target = shift;

    ## no critic (ProhibitNoStrict)
    no strict 'refs';
    no warnings 'redefine';
    *{"${target}::import"} =
      sub {

        my $class = shift;
        my $target = caller;

        Moo::Role->apply_roles_to_package( $target, $class );

        _install_tags( $target, $TAGSTORE{$class} );
      };

}


sub _install_tags {

    my ( $target, $tags ) = @_;

    if ( $TAGSTORE{$target} ) {

        push @{ $TAGSTORE{$target} }, @$tags;

    }

    else {

        $TAGSTORE{$target} = [@$tags];
        _install_tag_handler( $target );
    }

}

sub _install_tag_handler {

    my $target = shift;

    install_modifier(
        $target,
        after => has => sub {
            my ( $attrs, %attr ) = @_;

            my @attrs = ref $attrs ? @$attrs : $attrs;

            my $target = caller;

            my @tags = @{ $TAGSTORE{$target} };

            # we need to
            #  1) use the target package's around() function, and
            #  2) call it in that package's context.

	    ## no critic (ProhibitStringyEval)
            my $around = eval( "package $target; sub { goto &around }" );

            $around->(
                "_build__tags" => sub {
                    my $orig = shift;

                    my $tags = &$orig;

		    ## no critic (ProhibitAccessOfPrivateData)
                    for my $tag ( grep { exists $attr{$_} } @tags ) {
                        $tags->{$tag} = {} unless defined $tags->{$tag};
                        $tags->{$tag}{$_} = $attr{$tag} for @attrs;
                    }

                    return $tags;
                } );

        } );

}

use Sub::Name 'subname';

my $can = sub { ( shift )->next::can };

# need this to handle composition on top of inheritance
# see http://www.nntp.perl.org/group/perl.moose/2015/01/msg287{6,7,8}.html
around _build__tags => sub {

    # at this point, execution is at the bottom of the stack
    # of wrapped calls for the immediate composing class.

    # use the calling package as the starting point for the search up
    # the inheritance chain.  as this routine gets called from
    # different points, that'll change.

    # only run the original method when we've reached the very
    # end of the inheritance chain.  otherwise it will get run
    # for each class (as we bottom out here) which is incorrect.

    my $orig    = shift;
    my $package = caller;

    my $next = ( subname "${package}::_build__tags" => $can )->( $_[0] );

    return $next ? $next->( @_ ) : &$orig;
};


use namespace::clean -except => qw( import );

# because tag roles may be dynamically applied to objects, the entire
# chain must be followed.  TODO: cache it.
sub _build__tags {};
sub _tags { $_[0]->_build__tags };


1;

__END__

=head1 NAME

MooX::TaggedAttributes - Add a tag with an arbitrary value to a an attribute


=head1 SYNOPSIS

    # Create a Role used to apply the attributes
    package Tags;
    use Moo::Role;
    use MooX::TaggedAttributes -tags => [ qw( t1 t2 ) ];

    # Apply the role directly to a class
    package C1;
    use Tags;

    has c1 => ( is => 'ro', t1 => 1 );

    my $obj = C1->new;

    # get the value of the tag t1, applied to attribute a1
    $obj->_tags->{t1}{a1};

    # Apply the tags to a role
    package R1;
    use Tag1;

    has r1 => ( is => 'ro', t2 => 2 );

    # Use that role in a class
    package C2;
    use R1;

    has c2 => ( is => 'ro', t2 => sub { }  );

    # get the value of the tag t2, applied to attribute c2
    C2->new->_tags->{t2}{c2};

=head1 DESCRIPTION

This module attaches a tag-value pair to an attribute in a B<Moo>
class or role, and provides a interface to query which attributes have
which tags, and what the values are.

=head2 Tagging Attributes

To define a set of tags, create a special I<tag role>:

    package T1;
    use Moo::Role;
    use MooX::TaggedAttributes -tags => [ 't1' ];

    has a1 => ( is => 'ro', t1 => 'foo' );

If there's only one tag, it can be passed directly without being
wrapped in an array:

    package T2;
    use Moo::Role;
    use MooX::TaggedAttributes -tags => 't2';

    has a2 => ( is => 'ro', t2 => 'bar' );

A tag role is a standard B<Moo::Role> with added machinery to track
attribute tags.  As shown, attributes may be tagged in the tag role
as well as in modules which consume it.

Tag roles may be consumed just as ordinary roles, but in order for
role consumers to have the ability to assign tags to attributes, they
need to be consumed with the Perl B<use> statement, not with the B<with> statement.

Consuming with the B<with> statement I<will> propagate attributes with
existing tags, but won't provide the ability to tag new attributes.

This is correct:

    package R2;
    use Moo::Role;
    use T1;

    has r2 => ( is => 'ro', t1 => 'foo' );

    package R3;
    use Moo::Role;
    use R3;

    has r3 => ( is => 'ro', t1 => 'foo' );

The same goes for classes:

    package C2;
    use Moo;
    use T1;

    has c2 => ( is => 'ro', t1 => 'foo' );

Combining tag roles is as simple as B<use>'ing them in the new role:

    package T12;
    use T1;
    use T2;

    package C2;
    use Moo;
    use T12;

    has c2 => ( is => 'ro', t1 => 'foo', t2 => 'bar' );

=head2 Accessing tags

Objects are provided a B<_tags> method which returns a hash of hashes
keyed off of the tags and attribute names.  For example, for the
following code:

    package T;
    use Moo::Role;
    use MooX::TaggedAttributes -tags => [ qw( t1 t2 ) ];

    package C;
    use Moo;
    use T;

    has a => ( is => 'ro', t1 => 2 );
    has b => ( is => 'ro', t2 => 'foo' );

The tag structure returned by

    C->new->_tags

looks like

    { t1 => { a => 2 },
      t2 => { b => 'foo' },
    }

=head1 BUGS AND LIMITATIONS


No bugs have been reported.

Please report any bugs or feature requests to
C<bug-moox-taggedattributes@rt.cpan.org>, or through the web interface at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=MooX-TaggedAttributes>.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015 The Smithsonian Astrophysical Observatory

MooX::TaggedAttributes is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 AUTHOR

Diab Jerius  E<lt>djerius@cpan.orgE<gt>

