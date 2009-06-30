package DBIx::Class::Schema::Loader::DBI::MSSQL;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Carp::Clan qw/^DBIx::Class/;
use Class::C3;

our $VERSION = '0.04999_06';

=head1 NAME

DBIx::Class::Schema::Loader::DBI::MSSQL - DBIx::Class::Schema::Loader::DBI MSSQL Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options( debug => 1 );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _rebless {
    my $self = shift;

    $self->schema->storage->sql_maker->quote_char([qw/[ ]/])
        unless $self->schema->storage->sql_maker->quote_char;

    $self->schema->storage->sql_maker->name_sep('.')
        unless $self->schema->storage->sql_maker->name_sep;
}

sub _setup {
    my $self = shift;

    $self->next::method(@_);
    $self->{db_schema} ||= 'dbo';
}

# DBD::Sybase doesn't implement get_info properly
#sub _build_quoter  { [qw/[ ]/] }
sub _build_quoter  { '"' }
sub _build_namesep { '.' }

sub _table_pk_info {
    my ($self, $table) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_pkeys '$table'});
    $sth->execute;

    my @keydata;

    while (my $row = $sth->fetchrow_hashref) {
        push @keydata, lc $row->{COLUMN_NAME};
    }

    return \@keydata;
}

sub _table_fk_info {
    my ($self, $table) = @_;

    my ($local_cols, $remote_cols, $remote_table, @rels);
    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{sp_fkeys \@FKTABLE_NAME = '$table'});
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $fk = $row->{FK_NAME};
        push @{$local_cols->{$fk}}, lc $row->{FKCOLUMN_NAME};
        push @{$remote_cols->{$fk}}, lc $row->{PKCOLUMN_NAME};
        $remote_table->{$fk} = $row->{PKTABLE_NAME};
    }

    foreach my $fk (keys %$remote_table) {
        push @rels, {
                      local_columns => \@{$local_cols->{$fk}},
                      remote_columns => \@{$remote_cols->{$fk}},
                      remote_table => $remote_table->{$fk},
                    };

    }
    return \@rels;
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{SELECT CCU.CONSTRAINT_NAME, CCU.COLUMN_NAME FROM INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE CCU
                               JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS TC ON (CCU.CONSTRAINT_NAME = TC.CONSTRAINT_NAME)
                               JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE KCU ON (CCU.CONSTRAINT_NAME = KCU.CONSTRAINT_NAME AND CCU.COLUMN_NAME = KCU.COLUMN_NAME)
                               WHERE CCU.TABLE_NAME = '$table' AND CONSTRAINT_TYPE = 'UNIQUE' ORDER BY KCU.ORDINAL_POSITION});
    $sth->execute;
    my $constraints;
    while (my $row = $sth->fetchrow_hashref) {
        my $name = lc $row->{CONSTRAINT_NAME};
        my $col  = lc $row->{COLUMN_NAME};
        push @{$constraints->{$name}}, $col;
    }

    my @uniqs = map { [ $_ => $constraints->{$_} ] } keys %$constraints;
    return \@uniqs;
}

sub _extra_column_info {
    my ($self, $info) = @_;
    my %extra_info;

    my ($table, $column) = @$info{qw/TABLE_NAME COLUMN_NAME/};

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->prepare(qq{SELECT COLUMN_NAME 
                               FROM INFORMATION_SCHEMA.COLUMNS
                               WHERE COLUMNPROPERTY(object_id('$table', 'U'), '$column', 'IsIdentity') = 1 AND TABLE_NAME = '$table' AND COLUMN_NAME = '$column'
                              });
    $sth->execute();

    if ($sth->fetchrow_array) {
        $extra_info{is_auto_increment} = 1;
    }

    return \%extra_info;
}


=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>, L<DBIx::Class::Schema::Loader::Base>,
L<DBIx::Class::Schema::Loader::DBI>

=head1 AUTHOR

Justin Hunter C<justin.d.hunter@gmail.com>

=cut

1;
