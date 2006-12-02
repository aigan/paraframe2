#  $Id$  -*-perl-*-
package Para::Frame::DBIx::State;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se framework DBI Table class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Frame::DBIx::State - SQLSTATE codes

=cut

use strict;
use Carp qw( carp croak shortmess confess );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

#use Para::Frame::Reload;
use Para::Frame::Utils qw( throw catch debug datadump );

our %CLASS;
our %CODE;
our %LABEL;


#######################################################################

### SQLSTATE data taken from
# http://www.postgresql.org/docs/8.1/interactive/errcodes-appendix.html
# 2006-08-21 v8.1.4 using ODBC 2.0
#
our $DATA = <<'EOD';
Class 00 \u2014 Successful Completion
0	SUCCESSFUL COMPLETION	successful_completion
Class 01\u2014 Warning
1000	WARNING	warning
0100C	DYNAMIC RESULT SETS RETURNED	dynamic_result_sets_returned
1008	IMPLICIT ZERO BIT PADDING	implicit_zero_bit_padding
1003	NULL VALUE ELIMINATED IN SET FUNCTION	null_value_eliminated_in_set_function
1007	PRIVILEGE NOT GRANTED	privilege_not_granted
1006	PRIVILEGE NOT REVOKED	privilege_not_revoked
1004	STRING DATA RIGHT TRUNCATION	string_data_right_truncation
01P01	DEPRECATED FEATURE	deprecated_feature
Class 02\u2014 No Data (this is also a warning class per the SQL standard)
2000	NO DATA	no_data
2001	NO ADDITIONAL DYNAMIC RESULT SETS RETURNED	no_additional_dynamic_result_sets_returned
Class 03\u2014 SQL Statement Not Yet Complete
3000	SQL STATEMENT NOT YET COMPLETE	sql_statement_not_yet_complete
Class 08\u2014 Connection Exception
8000	CONNECTION EXCEPTION	connection_exception
8003	CONNECTION DOES NOT EXIST	connection_does_not_exist
8006	CONNECTION FAILURE	connection_failure
8001	SQLCLIENT UNABLE TO ESTABLISH SQLCONNECTION	sqlclient_unable_to_establish_sqlconnection
8004	SQLSERVER REJECTED ESTABLISHMENT OF SQLCONNECTION	sqlserver_rejected_establishment_of_sqlconnection
8007	TRANSACTION RESOLUTION UNKNOWN	transaction_resolution_unknown
08P01	PROTOCOL VIOLATION	protocol_violation
Class 09\u2014 Triggered Action Exception
9000	TRIGGERED ACTION EXCEPTION	triggered_action_exception
Class 0A\u2014 Feature Not Supported
0A000	FEATURE NOT SUPPORTED	feature_not_supported
Class 0B\u2014 Invalid Transaction Initiation
0B000	INVALID TRANSACTION INITIATION	invalid_transaction_initiation
Class 0F\u2014 Locator Exception
0F000	LOCATOR EXCEPTION	locator_exception
0F001	INVALID LOCATOR SPECIFICATION	invalid_locator_specification
Class 0L\u2014 Invalid Grantor
0L000	INVALID GRANTOR	invalid_grantor
0LP01	INVALID GRANT OPERATION	invalid_grant_operation
Class 0P\u2014 Invalid Role Specification
0P000	INVALID ROLE SPECIFICATION	invalid_role_specification
Class 21\u2014 Cardinality Violation
21000	CARDINALITY VIOLATION	cardinality_violation
Class 22\u2014 Data Exception
22000	DATA EXCEPTION	data_exception
2202E	ARRAY SUBSCRIPT ERROR	array_subscript_error
22021	CHARACTER NOT IN REPERTOIRE	character_not_in_repertoire
22008	DATETIME FIELD OVERFLOW	datetime_field_overflow
22012	DIVISION BY ZERO	division_by_zero
22005	ERROR IN ASSIGNMENT	error_in_assignment
2200B	ESCAPE CHARACTER CONFLICT	escape_character_conflict
22022	INDICATOR OVERFLOW	indicator_overflow
22015	INTERVAL FIELD OVERFLOW	interval_field_overflow
2201E	INVALID ARGUMENT FOR LOGARITHM	invalid_argument_for_logarithm
2201F	INVALID ARGUMENT FOR POWER FUNCTION	invalid_argument_for_power_function
2201G	INVALID ARGUMENT FOR WIDTH BUCKET FUNCTION	invalid_argument_for_width_bucket_function
22018	INVALID CHARACTER VALUE FOR CAST	invalid_character_value_for_cast
22007	INVALID DATETIME FORMAT	invalid_datetime_format
22019	INVALID ESCAPE CHARACTER	invalid_escape_character
2200D	INVALID ESCAPE OCTET	invalid_escape_octet
22025	INVALID ESCAPE SEQUENCE	invalid_escape_sequence
22P06	NONSTANDARD USE OF ESCAPE CHARACTER	nonstandard_use_of_escape_character
22010	INVALID INDICATOR PARAMETER VALUE	invalid_indicator_parameter_value
22020	INVALID LIMIT VALUE	invalid_limit_value
22023	INVALID PARAMETER VALUE	invalid_parameter_value
2201B	INVALID REGULAR EXPRESSION	invalid_regular_expression
22009	INVALID TIME ZONE DISPLACEMENT VALUE	invalid_time_zone_displacement_value
2200C	INVALID USE OF ESCAPE CHARACTER	invalid_use_of_escape_character
2200G	MOST SPECIFIC TYPE MISMATCH	most_specific_type_mismatch
22004	NULL VALUE NOT ALLOWED	null_value_not_allowed
22002	NULL VALUE NO INDICATOR PARAMETER	null_value_no_indicator_parameter
22003	NUMERIC VALUE OUT OF RANGE	numeric_value_out_of_range
22026	STRING DATA LENGTH MISMATCH	string_data_length_mismatch
22001	STRING DATA RIGHT TRUNCATION	string_data_right_truncation
22011	SUBSTRING ERROR	substring_error
22027	TRIM ERROR	trim_error
22024	UNTERMINATED C STRING	unterminated_c_string
2200F	ZERO LENGTH CHARACTER STRING	zero_length_character_string
22P01	FLOATING POINT EXCEPTION	floating_point_exception
22P02	INVALID TEXT REPRESENTATION	invalid_text_representation
22P03	INVALID BINARY REPRESENTATION	invalid_binary_representation
22P04	BAD COPY FILE FORMAT	bad_copy_file_format
22P05	UNTRANSLATABLE CHARACTER	untranslatable_character
Class 23\u2014 Integrity Constraint Violation
23000	INTEGRITY CONSTRAINT VIOLATION	integrity_constraint_violation
23001	RESTRICT VIOLATION	restrict_violation
23502	NOT NULL VIOLATION	not_null_violation
23503	FOREIGN KEY VIOLATION	foreign_key_violation
23505	UNIQUE VIOLATION	unique_violation
23514	CHECK VIOLATION	check_violation
Class 24\u2014 Invalid Cursor State
24000	INVALID CURSOR STATE	invalid_cursor_state
Class 25\u2014 Invalid Transaction State
25000	INVALID TRANSACTION STATE	invalid_transaction_state
25001	ACTIVE SQL TRANSACTION	active_sql_transaction
25002	BRANCH TRANSACTION ALREADY ACTIVE	branch_transaction_already_active
25008	HELD CURSOR REQUIRES SAME ISOLATION LEVEL	held_cursor_requires_same_isolation_level
25003	INAPPROPRIATE ACCESS MODE FOR BRANCH TRANSACTION	inappropriate_access_mode_for_branch_transaction
25004	INAPPROPRIATE ISOLATION LEVEL FOR BRANCH TRANSACTION	inappropriate_isolation_level_for_branch_transaction
25005	NO ACTIVE SQL TRANSACTION FOR BRANCH TRANSACTION	no_active_sql_transaction_for_branch_transaction
25006	READ ONLY SQL TRANSACTION	read_only_sql_transaction
25007	SCHEMA AND DATA STATEMENT MIXING NOT SUPPORTED	schema_and_data_statement_mixing_not_supported
25P01	NO ACTIVE SQL TRANSACTION	no_active_sql_transaction
25P02	IN FAILED SQL TRANSACTION	in_failed_sql_transaction
Class 26\u2014 Invalid SQL Statement Name
26000	INVALID SQL STATEMENT NAME	invalid_sql_statement_name
Class 27\u2014 Triggered Data Change Violation
27000	TRIGGERED DATA CHANGE VIOLATION	triggered_data_change_violation
Class 28\u2014 Invalid Authorization Specification
28000	INVALID AUTHORIZATION SPECIFICATION	invalid_authorization_specification
Class 2B\u2014 Dependent Privilege Descriptors Still Exist
2B000	DEPENDENT PRIVILEGE DESCRIPTORS STILL EXIST	dependent_privilege_descriptors_still_exist
2BP01	DEPENDENT OBJECTS STILL EXIST	dependent_objects_still_exist
Class 2D\u2014 Invalid Transaction Termination
2D000	INVALID TRANSACTION TERMINATION	invalid_transaction_termination
Class 2F\u2014 SQL Routine Exception
2F000	SQL ROUTINE EXCEPTION	sql_routine_exception
2F005	FUNCTION EXECUTED NO RETURN STATEMENT	function_executed_no_return_statement
2F002	MODIFYING SQL DATA NOT PERMITTED	modifying_sql_data_not_permitted
2F003	PROHIBITED SQL STATEMENT ATTEMPTED	prohibited_sql_statement_attempted
2F004	READING SQL DATA NOT PERMITTED	reading_sql_data_not_permitted
Class 34\u2014 Invalid Cursor Name
34000	INVALID CURSOR NAME	invalid_cursor_name
Class 38\u2014 External Routine Exception
38000	EXTERNAL ROUTINE EXCEPTION	external_routine_exception
38001	CONTAINING SQL NOT PERMITTED	containing_sql_not_permitted
38002	MODIFYING SQL DATA NOT PERMITTED	modifying_sql_data_not_permitted
38003	PROHIBITED SQL STATEMENT ATTEMPTED	prohibited_sql_statement_attempted
38004	READING SQL DATA NOT PERMITTED	reading_sql_data_not_permitted
Class 39\u2014 External Routine Invocation Exception
39000	EXTERNAL ROUTINE INVOCATION EXCEPTION	external_routine_invocation_exception
39001	INVALID SQLSTATE RETURNED	invalid_sqlstate_returned
39004	NULL VALUE NOT ALLOWED	null_value_not_allowed
39P01	TRIGGER PROTOCOL VIOLATED	trigger_protocol_violated
39P02	SRF PROTOCOL VIOLATED	srf_protocol_violated
Class 3B\u2014 Savepoint Exception
3B000	SAVEPOINT EXCEPTION	savepoint_exception
3B001	INVALID SAVEPOINT SPECIFICATION	invalid_savepoint_specification
Class 3D\u2014 Invalid Catalog Name
3D000	INVALID CATALOG NAME	invalid_catalog_name
Class 3F\u2014 Invalid Schema Name
3F000	INVALID SCHEMA NAME	invalid_schema_name
Class 40\u2014 Transaction Rollback
40000	TRANSACTION ROLLBACK	transaction_rollback
40002	TRANSACTION INTEGRITY CONSTRAINT VIOLATION	transaction_integrity_constraint_violation
40001	SERIALIZATION FAILURE	serialization_failure
40003	STATEMENT COMPLETION UNKNOWN	statement_completion_unknown
40P01	DEADLOCK DETECTED	deadlock_detected
Class 42\u2014 Syntax Error or Access Rule Violation
42000	SYNTAX ERROR OR ACCESS RULE VIOLATION	syntax_error_or_access_rule_violation
42601	SYNTAX ERROR	syntax_error
42501	INSUFFICIENT PRIVILEGE	insufficient_privilege
42846	CANNOT COERCE	cannot_coerce
42803	GROUPING ERROR	grouping_error
42830	INVALID FOREIGN KEY	invalid_foreign_key
42602	INVALID NAME	invalid_name
42622	NAME TOO LONG	name_too_long
42939	RESERVED NAME	reserved_name
42804	DATATYPE MISMATCH	datatype_mismatch
42P18	INDETERMINATE DATATYPE	indeterminate_datatype
42809	WRONG OBJECT TYPE	wrong_object_type
42703	UNDEFINED COLUMN	undefined_column
42883	UNDEFINED FUNCTION	undefined_function
42P01	UNDEFINED TABLE	undefined_table
42P02	UNDEFINED PARAMETER	undefined_parameter
42704	UNDEFINED OBJECT	undefined_object
42701	DUPLICATE COLUMN	duplicate_column
42P03	DUPLICATE CURSOR	duplicate_cursor
42P04	DUPLICATE DATABASE	duplicate_database
42723	DUPLICATE FUNCTION	duplicate_function
42P05	DUPLICATE PREPARED STATEMENT	duplicate_prepared_statement
42P06	DUPLICATE SCHEMA	duplicate_schema
42P07	DUPLICATE TABLE	duplicate_table
42712	DUPLICATE ALIAS	duplicate_alias
42710	DUPLICATE OBJECT	duplicate_object
42702	AMBIGUOUS COLUMN	ambiguous_column
42725	AMBIGUOUS FUNCTION	ambiguous_function
42P08	AMBIGUOUS PARAMETER	ambiguous_parameter
42P09	AMBIGUOUS ALIAS	ambiguous_alias
42P10	INVALID COLUMN REFERENCE	invalid_column_reference
42611	INVALID COLUMN DEFINITION	invalid_column_definition
42P11	INVALID CURSOR DEFINITION	invalid_cursor_definition
42P12	INVALID DATABASE DEFINITION	invalid_database_definition
42P13	INVALID FUNCTION DEFINITION	invalid_function_definition
42P14	INVALID PREPARED STATEMENT DEFINITION	invalid_prepared_statement_definition
42P15	INVALID SCHEMA DEFINITION	invalid_schema_definition
42P16	INVALID TABLE DEFINITION	invalid_table_definition
42P17	INVALID OBJECT DEFINITION	invalid_object_definition
Class 44\u2014 WITH CHECK OPTION Violation
44000	WITH CHECK OPTION VIOLATION	with_check_option_violation
Class 53\u2014 Insufficient Resources
53000	INSUFFICIENT RESOURCES	insufficient_resources
53100	DISK FULL	disk_full
53200	OUT OF MEMORY	out_of_memory
53300	TOO MANY CONNECTIONS	too_many_connections
Class 54\u2014 Program Limit Exceeded
54000	PROGRAM LIMIT EXCEEDED	program_limit_exceeded
54001	STATEMENT TOO COMPLEX	statement_too_complex
54011	TOO MANY COLUMNS	too_many_columns
54023	TOO MANY ARGUMENTS	too_many_arguments
Class 55\u2014 Object Not In Prerequisite State
55000	OBJECT NOT IN PREREQUISITE STATE	object_not_in_prerequisite_state
55006	OBJECT IN USE	object_in_use
55P02	CANT CHANGE RUNTIME PARAM	cant_change_runtime_param
55P03	LOCK NOT AVAILABLE	lock_not_available
Class 57\u2014 Operator Intervention
57000	OPERATOR INTERVENTION	operator_intervention
57014	QUERY CANCELED	query_canceled
57P01	ADMIN SHUTDOWN	admin_shutdown
57P02	CRASH SHUTDOWN	crash_shutdown
57P03	CANNOT CONNECT NOW	cannot_connect_now
Class 58\u2014 System Error (errors external to PostgreSQL itself)
58030	IO ERROR	io_error
58P01	UNDEFINED FILE	undefined_file
58P02	DUPLICATE FILE	duplicate_file
Class F0\u2014 Configuration File Error
F0000	CONFIG FILE ERROR	config_file_error
F0001	LOCK FILE EXISTS	lock_file_exists
Class P0\u2014 PL/pgSQL Error
P0000	PLPGSQL ERROR	plpgsql_error
P0001	RAISE EXCEPTION	raise_exception
Class XX\u2014 Internal Error
XX000	INTERNAL ERROR	internal_error
XX001	DATA CORRUPTED	data_corrupted
XX002	INDEX CORRUPTED	index_corrupted
EOD
  ;


#######################################################################

=head2 import

=cut

sub import
{
    open(my $fh, '<', \$DATA) or die $!;
    while(<$fh>)
    {
	if(/^Class (\w\w) ?\\u2014 (.*)/)
	{
	    $CLASS{$1} =
	    {
	     code => $1,
	     name => $2,
	     is_class => 1,
	    };
	}
	elsif(/^(\w+)\t(.*?)\t(.*)/)
	{
	    my $code_str = sprintf "%05s", $1;
	    my $class_str = substr($code_str,0,2);
	    $CODE{$code_str} =
	    {
	     code  => $code_str,
	     desc  => $2,
	     label => $3,
	     class => $CLASS{$class_str},
	    };

	    $LABEL{$3} = $CODE{$code_str};
	}
	else
	{
	    die "Malformed line: $_";
	}
    }

    $CLASS{'S1'} =
    {
     code => 'S1',
     name => 'General Error',
     is_class => 1,
    };

    $CODE{'S1000'} =
    {
     code => 'S1000',
     desc => 'GENERAL ERROR',
     label => 'general_error',
     class => $CLASS{'S1'},
    };

    $LABEL{'general_error'} = $CODE{'S1000'};

#    debug datadump( \%CODE );
}


#######################################################################

=head2 new

  $dbix->state()

=cut

sub new
{
    my( $this, $dbix ) = @_;
    my $class = ref($this) || $this;

    my $dbh = $dbix->dbh;
    my $state_code = $dbh->state;
    my $state = $CODE{$state_code} || $CODE{'S1000'};
#    or confess "Unrecognized state: $state_code";

    return bless
    {
     state  => $state,
     err    => $dbh->err,
     errstr => $dbh->errstr,
    }, $class;
}


#######################################################################

=head2 is

=cut

sub is
{
    my( $state, $code_in ) = @_;

    my $code;
    if( ref $code_in )
    {
	$code = $code_in;
    }
    else
    {
	my $code_str = sprintf "%05s", uc $code_in;
	$code = ($LABEL{lc $code_in} ||
		 $CODE{$code_str} ||
		 $CLASS{uc $code_in})
	  or die "Unrecognized state code: $code_in";
    }

    if( $code->{is_class} )
    {
	return($state->class_code eq $code->{'code'});
    }
    else
    {
	return($state->code eq $code->{'code'});
    }
}


#######################################################################

=head2 class_code

=cut

sub class_code
{
    return $_[0]->{'state'}{'class'}{'code'};
}


#######################################################################

=head2 class_name

=cut

sub class_name
{
    return $_[0]->{'state'}{'class'}{'name'};
}


#######################################################################

=head2 code

=cut

sub code
{
    return $_[0]->{'state'}{'code'};
}


#######################################################################

=head2 desc

=cut

sub desc
{
    return $_[0]->{'state'}{'desc'};
}


#######################################################################

=head2 label

=cut

sub label
{
    return $_[0]->{'state'}{'label'};
}


#######################################################################

=head2 is_error

=cut

sub is_error
{
    return $_[0]->{'err'} ? 1 : 0;
}


#######################################################################

=head2 is_success

=cut

sub is_success
{
    return $_[0]->{'err'} ? 0 : 1;
}


#######################################################################

1;

=head1 SEE ALSO

L<Para::Frame>, L<Para::Frame::DBIx>

=cut
