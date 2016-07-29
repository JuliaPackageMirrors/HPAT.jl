#=
Copyright (c) 2016, Intel Corporation
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
THE POSSIBILITY OF SUCH DAMAGE.
=#

function pattern_match_call_filter(linfo,f::GlobalRef, id, cond_e, num_cols,table_cols...)
    s = ""
    if f.name!=:__hpat_filter
        return s
    end
    # its an array of array. array[2:end] and table_cols... notation does that
    all_table_cols = table_cols[1]
    out_table_cols = all_table_cols[1:num_cols]
    in_table_cols = all_table_cols[(num_cols + 1):end]

    # For unique counter variables of filter
    unique_id = string(id)
    # assuming that all columns are of same size in a table
    column1_name = ParallelAccelerator.CGen.from_expr(in_table_cols[1],linfo)
    array_length = column1_name*"_array_length_filter" * unique_id
    s *= "int $array_length = " * column1_name * ".ARRAYLEN();\n"
    # Calculate final filtered array length
    write_index = "write_index_filter" * unique_id
    s *= "int $write_index = 1;\n"
    cond_e_arr = ParallelAccelerator.CGen.from_expr(cond_e, linfo)
    s *= "for (int index = 1 ; index < $array_length + 1 ; index++) { \n"
    s *= "if ( $cond_e_arr.ARRAYELEM(index) ){\n"
    # If condition satisfy copy all columns values
    for col_name in in_table_cols
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$arr_col_name.ARRAYELEM($write_index) =  $arr_col_name.ARRAYELEM(index); \n"
    end
    s *= "$write_index = $write_index + 1;\n"
    s *= "};\n" # if condition
    s *= "};\n" # for loop
    # After filtering we need to change the size of each array
    # And assign to output filter column tables
    for (index, col_name) in enumerate(in_table_cols)
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        out_arr_col_name = ParallelAccelerator.CGen.from_expr(out_table_cols[index],linfo)
        s *= "$arr_col_name.dims[0] =  $write_index - 1; \n"
        s *= "$out_arr_col_name = $arr_col_name ; \n"
    end
    return s
end

function pattern_match_call_filter(linfo,f::Any, id, cond_e, num_cols,table_cols...)
    return ""
end

function pattern_match_call_join_seq(linfo, f::GlobalRef, id, table_new_cols_len, table1_cols_len, table2_cols_len, table_columns...)
    s = ""
    if f.name!=:__hpat_join
        return s
    end
    # its an array of array. array[2:end] and table_cols... notation does that
    table_columns = table_columns[1]
    # extract columns of each table
    table_new_cols = table_columns[1:table_new_cols_len]
    table1_cols = table_columns[table_new_cols_len+1:table_new_cols_len+table1_cols_len]
    table2_cols = table_columns[table_new_cols_len+table1_cols_len+1:end]
    # to assign unique id to each variable
    join_rand = string(id)

    # assuming that all columns are of same size in a table
    # Also output table's length would be sum of both table length
    t1c1_length_join = "t1c1_length_join"*join_rand
    t2c1_length_join = "t2c1_length_join"*join_rand
    joined_table_length = "joined_table_length"*join_rand
    t1_c1_join = ParallelAccelerator.CGen.from_expr(table1_cols[1],linfo)
    t2_c1_join = ParallelAccelerator.CGen.from_expr(table2_cols[1],linfo)
    s *= "int $t1c1_length_join = $t1_c1_join.ARRAYLEN() ;\n "
    s *= "int $t2c1_length_join = $t2_c1_join.ARRAYLEN() ;\n "
    s *= "int $joined_table_length = $t2c1_length_join + $t2c1_length_join ;\n "
    # Instantiation of columns for  output table
    for col_name in table_new_cols
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$arr_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $joined_table_length);\n"
    end
    # Assuming that join is always on the first column of tables
    # Nested for loop implementation of join
    c_cond_sym = "=="
    table_new_counter_join = "table_new_counter_join" *join_rand
    s *= "int $table_new_counter_join = 1 ; \n"
    s *= "for (int table1_index = 1 ; table1_index < $t1c1_length_join+1 ; table1_index++) { \n"
    s *= "for (int table2_index = 1 ; table2_index < $t2c1_length_join+1 ; table2_index++) { \n"
    s *= "if ( $t1_c1_join.ARRAYELEM(table1_index) $c_cond_sym  $t2_c1_join.ARRAYELEM(table2_index) ){\n"
    count = 0;
    for (index, col_name) in enumerate(table1_cols)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index],linfo)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) = $table1_col_name.ARRAYELEM(table1_index); \n"
        count = count + 1
    end
    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index+count-1],linfo)
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) =  $table2_col_name.ARRAYELEM(table2_index); \n"
    end
    s *= "$table_new_counter_join++;\n"
    s *= "};\n" # join if condition
    s *= "};\n" # inner for loop
    s *= "};\n" # outer for loop
    # Change the size of each output array
    for col_name in table_new_cols
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$arr_col_name.dims[0] =  $table_new_counter_join - 1; \n"
    end
    # For debugging
    #s *= "for (int i = 1 ; i < $table_new_counter_join ; i++){ std::cout << psale_itemspss_item_sk.ARRAYELEM(i) << std::endl;}\n"
    return s
end

function pattern_match_call_join_seq(linfo, f::Any, id, table_new_len, table1_len, table2_len, table_columns...)
    return ""
end

function pattern_match_call_join(linfo, f::GlobalRef, id, table_new_cols_len, table1_cols_len, table2_cols_len, table_columns...)
    s = ""
    if f.name!=:__hpat_join
        return s
    end
    # TODO remove join random. Use join id/counter in domain pass and pass to this function
    HPAT_path = joinpath(dirname(@__FILE__), "..")
    HPAT_includes = string("\n#include \"", HPAT_path, "/deps/include/hpat_sort.h\"\n")
    ParallelAccelerator.CGen.addCgenUserOptions(ParallelAccelerator.CGen.CgenUserOptions(HPAT_includes))

    # its an array of array. array[2:end] and table_cols... notation does that
    table_columns = table_columns[1]
    # extract columns of each table
    table_new_cols = table_columns[1:table_new_cols_len]
    table1_cols = table_columns[table_new_cols_len+1:table_new_cols_len+table1_cols_len]
    table2_cols = table_columns[table_new_cols_len+table1_cols_len+1:end]
    join_rand = string(id)

    # Sending counts for both tables
    scount_t1 = "scount_t1_"*join_rand
    scount_t2 = "scount_t2_"*join_rand

    scount_t1_tmp = "scount_t1_tmp_"*join_rand
    scount_t2_tmp = "scount_t2_tmp_"*join_rand
    s *= "int * $scount_t1;\n"
    s *= "int * $scount_t2;\n"

    s *= "int * $scount_t1_tmp;\n"
    s *= "int * $scount_t2_tmp;\n"

    s *= "$scount_t1 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount_t1, 0, sizeof(int)*__hpat_num_pes);\n"

    s *= "$scount_t1_tmp = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount_t1_tmp, 0, sizeof(int)*__hpat_num_pes);\n"

    s *= "$scount_t2 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount_t2, 0, sizeof(int)*__hpat_num_pes);\n"

    s *= "$scount_t2_tmp = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount_t2_tmp, 0, sizeof(int)*__hpat_num_pes);\n"

    # Receiving counts for both tables
    rsize_t1 = "rsize_t1_"*join_rand
    rsize_t2 = "rsize_t2_"*join_rand
    s *= "int  $rsize_t1 = 0;\n"
    s *= "int  $rsize_t2 = 0;\n"

    rcount_t1 = "rcount_t1_"*join_rand
    rcount_t2 = "rcount_t2_"*join_rand
    s *= "int * $rcount_t1;\n"
    s *= "int * $rcount_t2;\n"
    s *= "$rcount_t1 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "$rcount_t2 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"

    # Displacement arrays for both tables
    sdis_t1 = "sdis_t1_"*join_rand
    rdis_t1 = "rdis_t1_"*join_rand
    s *= "int * $sdis_t1;\n"
    s *= "int * $rdis_t1;\n"
    s *= "$sdis_t1 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "$rdis_t1 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    sdis_t2 = "sdis_t2_"*join_rand
    rdis_t2 = "rdis_t2_"*join_rand
    s *= "int * $sdis_t2;\n"
    s *= "int * $rdis_t2;\n"
    s *= "$sdis_t2 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "$rdis_t2 = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"

    t1c1_length_join = "t1c1_length_join"*join_rand
    t2c1_length_join = "t2c1_length_join"*join_rand

    t1_c1_join = ParallelAccelerator.CGen.from_expr(table1_cols[1],linfo)
    t2_c1_join = ParallelAccelerator.CGen.from_expr(table2_cols[1],linfo)
    s *= "int $t1c1_length_join = $t1_c1_join.ARRAYLEN() ;\n "
    s *= "int $t2c1_length_join = $t2_c1_join.ARRAYLEN() ;\n "

    # Starting for table 1
    s *= "for (int i = 1 ; i <  $t1c1_length_join + 1 ; i++){\n"
    s *= "int node_id = $t1_c1_join.ARRAYELEM(i) % __hpat_num_pes ;\n"
    s *= "$scount_t1[node_id]++;"
    s *= "}\n"

    s *= "$sdis_t1[0]=0;\n"
    s *= "for(int i=1;i < __hpat_num_pes;i++){\n"
    s *= "$sdis_t1[i]=$scount_t1[i-1] + $sdis_t1[i-1];\n"
    s *= "}\n"

    s *= "MPI_Alltoall($scount_t1,1,MPI_INT,$rcount_t1,1,MPI_INT,MPI_COMM_WORLD);\n"

    # Declaring temporary buffers
    # Assuming that all of them have same length
    # TODO do insertion sort like a combiner in Hadoop
    for (index, col_name) in enumerate(table1_cols)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table1_col_name_tmp = table1_col_name * "_tmp_join_" * join_rand
        s *= "j2c_array< int64_t > $table1_col_name_tmp = j2c_array<int64_t>::new_j2c_array_1d(NULL, $t1c1_length_join );\n"
    end
    s *= "for (int i = 1 ; i <  $t1c1_length_join + 1 ; i++){\n"
    s *= "int node_id = $t1_c1_join.ARRAYELEM(i) % __hpat_num_pes ;\n"
    for (index, col_name) in enumerate(table1_cols)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table1_col_name_tmp = table1_col_name * "_tmp_join_" * join_rand
        s *= "$table1_col_name_tmp.ARRAYELEM($sdis_t1[node_id]+$scount_t1_tmp[node_id]+1) = $table1_col_name.ARRAYELEM(i);\n"
    end
    s *= "$scount_t1_tmp[node_id]++;\n"
    s *= "}\n"

    # Starting for table 2
    s *= "for (int i = 1 ; i <  $t2c1_length_join + 1 ; i++){\n"
    s *= "int node_id = $t2_c1_join.ARRAYELEM(i) % __hpat_num_pes ;\n"
    s *= "$scount_t2[node_id]++;"
    s *= "}\n"

    s *= "$sdis_t2[0]=0;\n"
    s *= "for(int i=1;i < __hpat_num_pes;i++){\n"
    s *= "$sdis_t2[i]=$scount_t2[i-1] + $sdis_t2[i-1];\n"
    s *= "}\n"

    s *= "MPI_Alltoall($scount_t2,1,MPI_INT,$rcount_t2,1,MPI_INT,MPI_COMM_WORLD);\n"

    # Declaring temporary buffers
    for (index, col_name) in enumerate(table2_cols)
        table2_col_name =ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table2_col_name_tmp =  table2_col_name * "_tmp_join_" * join_rand
        s *= "j2c_array< int64_t > $table2_col_name_tmp = j2c_array<int64_t>::new_j2c_array_1d(NULL, $t2c1_length_join);\n"
    end

    s *= "for (int i = 1 ; i <   $t2c1_length_join + 1 ; i++){\n"
    s *= "int node_id = $t2_c1_join.ARRAYELEM(i) % __hpat_num_pes ;\n"
    for (index, col_name) in enumerate(table2_cols)
        table2_col_name =ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table2_col_name_tmp =  table2_col_name * "_tmp_join_" * join_rand
        s *= "$table2_col_name_tmp.ARRAYELEM($sdis_t2[node_id]+$scount_t2_tmp[node_id]+1) = $table2_col_name.ARRAYELEM(i);\n"
    end
    s *= "$scount_t2_tmp[node_id]++;\n"
    s *= "}\n"

    # Caculating displacements for both tables
    s *= """
              $rdis_t1[0]=0;
              $rdis_t2[0]=0;
              for(int i=1;i < __hpat_num_pes;i++){
                  $rdis_t1[i]=$rcount_t1[i-1] + $rdis_t1[i-1];
                  $rdis_t2[i]=$rcount_t2[i-1] + $rdis_t2[i-1];
              }
        """

    # Summing up receiving counts
    s *= """
            for(int i=0;i<__hpat_num_pes;i++){
                $rsize_t1=$rsize_t1 + $rcount_t1[i];
                $rsize_t2=$rsize_t2 + $rcount_t2[i];
              }
        """
    for (index, col_name) in enumerate(table1_cols)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table1_col_name_tmp = table1_col_name *"_tmp_join_" * join_rand
        s *= " j2c_array< int64_t > rbuf_$table1_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $rsize_t1);\n"
        s *= """ MPI_Alltoallv($table1_col_name_tmp.getData(), $scount_t1, $sdis_t1, MPI_INT64_T,
                                     rbuf_$table1_col_name.getData(), $rcount_t1, $rdis_t1, MPI_INT64_T, MPI_COMM_WORLD);
                     """
        s *= " $table1_col_name = rbuf_$table1_col_name; \n"
    end
    # delete [] tmp_table1_col_name

    for (index, col_name) in enumerate(table2_cols)
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        table2_col_name_tmp = table2_col_name * "_tmp_join_" * join_rand
        s *= " j2c_array< int64_t > rbuf_$table2_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $rsize_t2);\n"
        s *= """ MPI_Alltoallv($table2_col_name_tmp.getData(), $scount_t2, $sdis_t2, MPI_INT64_T,
                                     rbuf_$table2_col_name.getData(), $rcount_t2, $rdis_t2, MPI_INT64_T, MPI_COMM_WORLD);
                     """
        s *= " $table2_col_name = rbuf_$table2_col_name; \n"
    end
    # delete [] tmp_table2_col_name

    table_new_counter_join = "table_new_counter_join" *join_rand
    s *= "int $table_new_counter_join = 1 ; \n"
    count = 0;
    # Initiatilizing new table(output table) arrays
    for (index, col_name) in enumerate(table1_cols)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index],linfo)
        s *= "$table_new_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $rsize_t1 + $rsize_t2);\n"
        count = count + 1
    end
    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index+count-1],linfo)
        s *= "$table_new_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $rsize_t1 + $rsize_t2);\n"
    end
    # Use any sorting algorithm here before merging
    # Right now using simple bubble sort
    # TODO add tim sort here too
    j2c_type_t1 = get_j2c_type_from_array(table1_cols[1],linfo)
    j2c_type_t2 = get_j2c_type_from_array(table2_cols[1],linfo)
    t1_length = length(table1_cols)
    t2_length = length(table2_cols)
    t1_all_arrays = "t1_all_arrays" * join_rand
    t2_all_arrays = "t2_all_arrays" * join_rand
    s *= "$j2c_type_t1 * $t1_all_arrays[$t1_length - 1];\n"
    s *= "$j2c_type_t2 * $t2_all_arrays[$t2_length - 1];\n"
    for (index, col_name) in enumerate(table1_cols)
        if index == 1
            continue
        end
        arr_index = index - 2
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$t1_all_arrays [$arr_index] = ( $j2c_type_t1 *) $table1_col_name.getData();\n"
    end

    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        arr_index = index - 2
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$t2_all_arrays [$arr_index] = ( $j2c_type_t2 *) $table2_col_name.getData();\n"
    end
    s *= "__hpat_timsort(( $j2c_type_t1 *) $t1_c1_join.getData(), $rsize_t1 , $t1_all_arrays, $t1_length - 1);\n"
    s *= "__hpat_timsort(( $j2c_type_t2 *) $t2_c1_join.getData(), $rsize_t2 , $t2_all_arrays, $t2_length - 1);\n"
    # s *= "__hpat_quicksort($t1_all_arrays,$t1_length - 1, ( $j2c_type_t1 *) $t1_c1_join.getData(), 0, $rsize_t1 - 1);\n"
    # s *= "__hpat_quicksort($t2_all_arrays,$t2_length - 1, ( $j2c_type_t2 *) $t2_c1_join.getData(), 0, $rsize_t2 - 1);\n"

    #s *= "qsort($t2_c1_join.getData(),$rsize_t2, sizeof( $j2c_type_t2 ), __hpat_compare_qsort_$j2c_type_t2);\n"
    # after the arrays has been sorted merge them
    # I used algorithm from here www.dcs.ed.ac.uk/home/tz/phd/thesis/node20.htm
    left = "left_join_table_" * join_rand
    right = "right_join_table_" * join_rand
    s *= "int $left = 1;\n"
    s *= "int $right = 1;\n"
    s *= "while ( ($left < $rsize_t1 + 1) && ($right < $rsize_t2 + 1) ){\n"
    s *= "if($t1_c1_join.ARRAYELEM($left) == $t2_c1_join.ARRAYELEM($right)){\n"
    count = 0
    for (index, col_name) in enumerate(table1_cols)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index],linfo)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) = $table1_col_name.ARRAYELEM($left); \n"
        count = count + 1
    end
    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index+count-1],linfo)
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) =  $table2_col_name.ARRAYELEM($right); \n"
    end
    s *= "$table_new_counter_join++;\n"

    s *= "int tmp_$left = $left + 1 ;\n"
    s *= "while((tmp_$left < $rsize_t1 + 1) && ($t1_c1_join.ARRAYELEM(tmp_$left) == $t2_c1_join.ARRAYELEM($right))){\n"
    count = 0
    for (index, col_name) in enumerate(table1_cols)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index],linfo)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) = $table1_col_name.ARRAYELEM(tmp_$left); \n"
        count = count + 1
    end
    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index+count-1],linfo)
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) =  $table2_col_name.ARRAYELEM($right); \n"
    end
    s *= "tmp_$left++;\n"
    s *= "$table_new_counter_join++;\n"
    s *= "}\n"

    s *= "int tmp_$right = $right + 1 ;\n"
    s *= "while((tmp_$right < $rsize_t2 + 1) && ($t1_c1_join.ARRAYELEM($left) == $t2_c1_join.ARRAYELEM(tmp_$right))){\n"
    count = 0
    for (index, col_name) in enumerate(table1_cols)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index],linfo)
        table1_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) = $table1_col_name.ARRAYELEM($left); \n"
        count = count + 1
    end
    for (index, col_name) in enumerate(table2_cols)
        if index == 1
            continue
        end
        table_new_col_name = ParallelAccelerator.CGen.from_expr(table_new_cols[index+count-1],linfo)
        table2_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.ARRAYELEM($table_new_counter_join) =  $table2_col_name.ARRAYELEM(tmp_$right); \n"
    end
    s *= "tmp_$right++;\n"
    s *= "$table_new_counter_join++;\n"
    s *= "}\n"

    s *= "$left++;\n"
    s *= "$right++;\n"
    s *= "}\n" # if condition
    s *= "else if ($t1_c1_join.ARRAYELEM($left) < $t2_c1_join.ARRAYELEM($right))\n"
    s *= "$left++;\n"
    s *= "else\n"
    s *= "$right++;\n"
    s *= "}\n" # while condition

    # fixing size of arrays after joining
    for col_name in table_new_cols
        table_new_col_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        s *= "$table_new_col_name.dims[0] = $table_new_counter_join - 1;\n"
    end

    return s
end

function pattern_match_call_join(linfo, f::Any, id, table_new_len, table1_len, table2_len, table_columns...)
    return ""
end

function pattern_match_call_agg_seq(linfo, f::GlobalRef,  id, groupby_key, num_exprs, expr_func_output_list...)
    s = ""
    if f.name!=:__hpat_aggregate
        return s
    end
    HPAT_path = joinpath(dirname(@__FILE__), "..")
    HPAT_includes = string("\n#include <unordered_map>\n")
    ParallelAccelerator.CGen.addCgenUserOptions(ParallelAccelerator.CGen.CgenUserOptions(HPAT_includes))

    expr_func_output_list = expr_func_output_list[1]
    exprs_list = expr_func_output_list[1:num_exprs]
    funcs_list = expr_func_output_list[num_exprs+1:(2*num_exprs)]
    agg_rand = string(id)
    # first element of output list is the groupbykey column
    output_cols_list = expr_func_output_list[(2*num_exprs)+1 : end]
    agg_key_col_input = ParallelAccelerator.CGen.from_expr(groupby_key, linfo)
    agg_key_col_output = ParallelAccelerator.CGen.from_expr(output_cols_list[1], linfo)
    # Temporaty map for each column
    for (index, value) in enumerate(output_cols_list)
        table_new_col_name = ParallelAccelerator.CGen.from_expr(value,linfo)
        s *= "std::unordered_map<int,int> temp_map_$table_new_col_name ;\n"
    end
    agg_key_map_temp = "temp_map_$agg_key_col_output"
    s *= "for(int i = 1 ; i < $agg_key_col_input.ARRAYLEN() + 1 ; i++){\n"
    s *= "$agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)] = $agg_key_col_input.ARRAYELEM(i);\n"
    for (index, func) in enumerate(funcs_list)
        column_name = ""
        expr_name = ParallelAccelerator.CGen.from_expr(exprs_list[index],linfo)
        map_name = "temp_map_" * ParallelAccelerator.CGen.from_expr(output_cols_list[index+1],linfo)
        s *= return_reduction_string_with_closure(agg_key_col_input, expr_name, map_name, func)
    end
    s *= "}\n"
    # Initializing new columns
    for col_name in output_cols_list
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name, linfo)
        s *= "$arr_col_name = j2c_array<int64_t>::new_j2c_array_1d(NULL, $agg_key_map_temp.size());\n"
    end
    # copy back the values from map into arrays
    counter_agg = "counter_agg$agg_rand"
    s *= "int $counter_agg = 1;\n"
    s *= "for(auto i : $agg_key_map_temp){\n"
    for (index, value) in enumerate(output_cols_list)
        map_name = ParallelAccelerator.CGen.from_expr(value, linfo)
        s *= "$map_name.ARRAYELEM($counter_agg) = temp_map_$map_name[i.first];\n"
    end
    s *= "$counter_agg++;\n"
    s *= "}\n"
    # Debugging
    # s *= "for (int i = 1 ; i < $counter_agg ; i++){ std::cout << pcustomer_i_classpid3.ARRAYELEM(i) << std::endl;}\n"
    return s
end

function pattern_match_call_agg_seq(linfo, f::Any, id,  groupby_key, num_exprs, exprs_func_list...)
    return ""
end

function pattern_match_call_agg(linfo, f::GlobalRef,  id, groupby_key, num_exprs, expr_func_output_list...)
    s = ""
    if f.name!=:__hpat_aggregate
        return s
    end
    # TODO remove aggregate random. Use aggregate id/counter in domain pass and pass to this function
    HPAT_path = joinpath(dirname(@__FILE__), "..")
    HPAT_includes = string("\n#include <unordered_map>\n")
    ParallelAccelerator.CGen.addCgenUserOptions(ParallelAccelerator.CGen.CgenUserOptions(HPAT_includes))

    expr_func_output_list = expr_func_output_list[1]
    exprs_list = expr_func_output_list[1:num_exprs]
    funcs_list = expr_func_output_list[num_exprs+1:(2*num_exprs)]
    agg_rand = string(id)
    # first element of output list is the groupbykey column
    output_cols_list = expr_func_output_list[(2*num_exprs)+1 : end]
    agg_key_col_input = ParallelAccelerator.CGen.from_expr(groupby_key, linfo)
    agg_key_col_output = ParallelAccelerator.CGen.from_expr(output_cols_list[1], linfo)
    agg_key_col_input_len = "agg_key_col_input_len_"*agg_rand
    s *= "int $agg_key_col_input_len = $agg_key_col_input.ARRAYLEN();\n"

    # Sending counts
    scount = "scount_"*agg_rand
    s *= "int * $scount;\n"
    s *= "$scount = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount, 0, sizeof(int)*__hpat_num_pes);\n"

    scount_tmp = "scount_tmp_"*agg_rand
    s *= "int * $scount_tmp;\n"
    s *= "$scount_tmp = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "memset ($scount_tmp, 0, sizeof(int)*__hpat_num_pes);\n"

    # Receiving counts
    rsize = "rsize_"*agg_rand
    s *= "int  $rsize = 0;\n"
    rcount = "rcount_"*agg_rand
    s *= "int * $rcount;\n"
    s *= "$rcount = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"

    # Displacement arrays for both tables
    sdis = "sdis_"*agg_rand
    rdis = "rdis_"*agg_rand
    s *= "int * $sdis;\n"
    s *= "int * $rdis;\n"
    s *= "$sdis = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"
    s *= "$rdis = (int*)malloc(sizeof(int)*__hpat_num_pes);\n"

    agg_key_map_temp = "temp_map_$agg_key_col_output"
    s *= "std::unordered_map<int,int> $agg_key_map_temp ;\n"
    agg_temp_counter = "agg_temp_counter_" * agg_rand
    s *= "int $agg_temp_counter = 0;"
    # Counting displacements for table
    s *= "for (int i = 1 ; i <  $agg_key_col_input_len + 1 ; i++){\n"
    s *= "if ($agg_key_map_temp.find($agg_key_col_input.ARRAYELEM(i)) == $agg_key_map_temp.end()){\n"
    s *= "$agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)] = 1;\n"
    s *= "int node_id = $agg_key_col_input.ARRAYELEM(i) % __hpat_num_pes ;\n"
    s *= "$scount[node_id]++;\n"
    s *= "$agg_temp_counter++;\n"
    s *= "}\n"
    s *= "}\n"

    s *= "$sdis[0]=0;\n"
    s *= "for(int i=1;i < __hpat_num_pes;i++){\n"
    s *= "$sdis[i]=$scount[i-1] + $sdis[i-1];\n"
    s *= "}\n"

    s *= "MPI_Alltoall($scount,1,MPI_INT,$rcount,1,MPI_INT,MPI_COMM_WORLD);\n"

    s *= "$agg_key_map_temp.clear();\n"
    # Caculating displacements
    s *= """
                  $rdis[0]=0;
                  for(int i=1;i < __hpat_num_pes;i++){
                      $rdis[i]=$rcount[i-1] + $rdis[i-1];
                  }
            """

    # Summing receiving counts
    s *= """
              for(int i=0;i<__hpat_num_pes;i++){
                  $rsize = $rsize + $rcount[i];
              }
            """

    # First column is groupbykey which is handled separately
    agg_key_col_input_tmp = agg_key_col_input * "_tmp_agg_" * agg_rand
    j2c_type = get_j2c_type_from_array(groupby_key,linfo)
    s *= "j2c_array< $j2c_type > $agg_key_col_input_tmp = j2c_array< $j2c_type >::new_j2c_array_1d(NULL, $agg_temp_counter);\n"
    for (index, col_name) in enumerate(exprs_list)
        expr_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        expr_name_tmp = expr_name * "_tmp_agg_" * agg_rand
        j2c_type = get_j2c_type_from_array(output_cols_list[index + 1 ],linfo)
        s *= "j2c_array< $j2c_type > $expr_name_tmp = j2c_array< $j2c_type >::new_j2c_array_1d(NULL, $agg_temp_counter);\n"
    end

    s *= "for(int i = 1 ; i < $agg_key_col_input.ARRAYLEN() + 1 ; i++){\n"
    s *= "int node_id = $agg_key_col_input.ARRAYELEM(i) % __hpat_num_pes ;\n"
    s *= "if ($agg_key_map_temp.find($agg_key_col_input.ARRAYELEM(i)) == $agg_key_map_temp.end()){\n"
    agg_write_index = "agg_write_index_" * agg_rand
    s *= "int $agg_write_index =  $sdis[node_id]+$scount_tmp[node_id]+1 ;\n"
    s *= "$agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)] = $agg_write_index ;\n"
    s *= "$agg_key_col_input_tmp.ARRAYELEM($agg_write_index) = $agg_key_col_input.ARRAYELEM(i);\n"
    for (index, func) in enumerate(funcs_list)
        expr_name = ParallelAccelerator.CGen.from_expr(exprs_list[index],linfo)
        expr_name_tmp = expr_name * "_tmp_agg_" * agg_rand
        s *= return_combiner_string_with_closure_first_elem(expr_name_tmp, expr_name, func, agg_write_index)
    end
    s *= "$scount_tmp[node_id]++;\n"
    s *= "}\n"
    s *= "else{\n"
    current_write_index = "current_write_index" * agg_rand
    s *= "int $current_write_index = $agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)]; \n"
    for (index, func) in enumerate(funcs_list)
        expr_name = ParallelAccelerator.CGen.from_expr(exprs_list[index],linfo)
        expr_name_tmp = expr_name * "_tmp_agg_" * agg_rand
        s *= return_combiner_string_with_closure_second_elem(expr_name_tmp, expr_name, func, current_write_index)
    end
    s *= "}\n"
    s *= "}\n"
    s *= "$agg_key_map_temp.clear();\n"

    # First column is groupbykey which is handled separately
    # After mpi_alltoallv the length of agg_key_col_input is changed. Don't use agg_key_col_input_len
    mpi_type = get_mpi_type_from_array(groupby_key,linfo)
    j2c_type = get_j2c_type_from_array(groupby_key,linfo)
    s *= " j2c_array< $j2c_type > rbuf_$agg_key_col_input = j2c_array< $j2c_type >::new_j2c_array_1d(NULL, $rsize);\n"
    s *= """ MPI_Alltoallv($agg_key_col_input_tmp.getData(), $scount, $sdis, $mpi_type,
                                         rbuf_$agg_key_col_input.getData(), $rcount, $rdis, $mpi_type, MPI_COMM_WORLD);
                         """
    s *= " $agg_key_col_input = rbuf_$agg_key_col_input; \n"

    for (index, col_name) in enumerate(exprs_list)
        mpi_type = get_mpi_type_from_array(output_cols_list[index + 1], linfo)
        j2c_type = get_j2c_type_from_array(output_cols_list[index + 1], linfo)
        expr_name = ParallelAccelerator.CGen.from_expr(col_name,linfo)
        expr_name_tmp = expr_name * "_tmp_agg_" * agg_rand
        s *= " j2c_array< $j2c_type > rbuf_$expr_name = j2c_array< $j2c_type >::new_j2c_array_1d(NULL, $rsize);\n"
        s *= """ MPI_Alltoallv($expr_name_tmp.getData(), $scount, $sdis, $mpi_type,
                                         rbuf_$expr_name.getData(), $rcount, $rdis, $mpi_type, MPI_COMM_WORLD);
                         """
    end
    # delete [] expr_name_tmp

    for col_name in output_cols_list
        j2c_type = get_j2c_type_from_array(col_name,linfo)
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name, linfo)
        s *= "$arr_col_name = j2c_array< $j2c_type >::new_j2c_array_1d(NULL, $agg_key_col_input.ARRAYLEN());\n"
    end

    agg_write_index = "agg_write_index_" * agg_rand
    s *= "int $agg_write_index = 1;"
    s *= "for(int i = 1 ; i < $agg_key_col_input.ARRAYLEN() + 1 ; i++){\n"
    s *= "if ($agg_key_map_temp.find($agg_key_col_input.ARRAYELEM(i)) == $agg_key_map_temp.end()){"
    s *= "$agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)] = $agg_write_index ;\n"
    col_name = ParallelAccelerator.CGen.from_expr(output_cols_list[1], linfo)
    s *= "$col_name.ARRAYELEM($agg_write_index) = $agg_key_col_input.ARRAYELEM(i);\n"
    for (index, func) in enumerate(funcs_list)
        expr_name = ParallelAccelerator.CGen.from_expr(exprs_list[index],linfo)
        rbuf_expr_name = "rbuf_" * expr_name
        new_col_name = ParallelAccelerator.CGen.from_expr(output_cols_list[index + 1], linfo)
        s *= return_reduction_string_with_closure_first_elem(new_col_name, rbuf_expr_name, func, agg_write_index)
    end
    s *= "$agg_write_index++;\n"
    s *= "}\n"
    s *= "else{\n"
    current_write_index = "current_write_index" * agg_rand
    s *= "int $current_write_index = $agg_key_map_temp[$agg_key_col_input.ARRAYELEM(i)]; \n"
    for (index, func) in enumerate(funcs_list)
        expr_name = ParallelAccelerator.CGen.from_expr(exprs_list[index],linfo)
        rbuf_expr_name = "rbuf_" * expr_name
        new_col_name = ParallelAccelerator.CGen.from_expr(output_cols_list[index + 1], linfo)
        s *= return_reduction_string_with_closure_second_elem(new_col_name, rbuf_expr_name, func, current_write_index)
    end
    s *= "}\n"
    s *= "}\n"
    counter_agg = "counter_agg$agg_rand"
    s *= "int $counter_agg = $agg_key_map_temp.size();\n"
    for col_name in output_cols_list
        j2c_type = get_j2c_type_from_array(col_name,linfo)
        arr_col_name = ParallelAccelerator.CGen.from_expr(col_name, linfo)
        s *= "$arr_col_name.dims[0] = $counter_agg ;\n"
    end
    return s
end

function pattern_match_call_agg(linfo, f::Any, groupby_key, num_exprs, exprs_func_list...)
    return ""
end

# TODO Combine all below five functions into one.
function return_reduction_string_with_closure(agg_key_col_input,expr_arr,agg_map,func)
    s = ""
    if string(func) == "Main.length"
        s *= "if ($agg_map.find($agg_key_col_input.ARRAYELEM(i)) == $agg_map.end())\n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] = 1;\n"
        s *= "else \n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] += 1;\n\n"
    elseif string(func) == "Main.sum"
        s *= "if ($agg_map.find($agg_key_col_input.ARRAYELEM(i)) == $agg_map.end())\n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] = $expr_arr.ARRAYELEM(i) ;\n"
        s *= "else \n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] +=  $expr_arr.ARRAYELEM(i)  ;\n\n"
    elseif string(func) == "Main.max"
        s *= "if ($agg_map.find($agg_key_col_input.ARRAYELEM(i)) == $agg_map.end())){\n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] = $expr_arr.ARRAYELEM(i) ;}\n"
        s *= "else{ \n"
        s *= "if (agg_map_count[$agg_key_col_input.ARRAYELEM(i)] < $expr_arr.ARRAYELEM(i) ) \n"
        s *= "$agg_map[$agg_key_col_input.ARRAYELEM(i)] = $expr_arr.ARRAYELEM(i) ;}\n\n"
    end
    return s
end

function return_combiner_string_with_closure_first_elem(new_column_name,expr_arr,func,write_index)
    s = ""
    if string(func) == "Main.length"
        s *= "$new_column_name.ARRAYELEM($write_index) = 1 ;\n"
    elseif string(func) == "Main.sum"
        s *= "$new_column_name.ARRAYELEM($write_index) = $expr_arr.ARRAYELEM(i) ;\n"
    elseif string(func) == "Main.max"
        s *= "$new_column_name.ARRAYELEM($write_index) = $expr_arr.ARRAYELEM(i) ;}\n"
    end
    return s
end

function return_combiner_string_with_closure_second_elem(new_column_name,expr_arr,func, current_index)
    s = ""
    if string(func) == "Main.length"
        s *= "$new_column_name.ARRAYELEM($current_index) += 1 ; \n"
    elseif string(func) == "Main.sum"
        s *= "$new_column_name.ARRAYELEM($current_index) +=  $expr_arr.ARRAYELEM(i)  ;\n\n"
    elseif string(func) == "Main.max"
        s *= "if ($new_column_name.ARRAYELEM($current_index) < $expr_arr.ARRAYELEM(i)) \n"
        s *= "$new_column_name.ARRAYELEM($current_index) = $expr_arr.ARRAYELEM(i) ;}\n\n"
    end
    return s
end

function return_reduction_string_with_closure_first_elem(new_column_name,expr_arr,func,write_index)
    s = ""
    if string(func) == "Main.length"
        s *= "$new_column_name.ARRAYELEM($write_index) = $expr_arr.ARRAYELEM(i);\n"
    elseif string(func) == "Main.sum"
        s *= "$new_column_name.ARRAYELEM($write_index) = $expr_arr.ARRAYELEM(i) ;\n"
    elseif string(func) == "Main.max"
        s *= "$new_column_name.ARRAYELEM($write_index) = $expr_arr.ARRAYELEM(i) ;}\n"
    end
    return s
end

function return_reduction_string_with_closure_second_elem(new_column_name,expr_arr,func, current_index)
    s = ""
    if string(func) == "Main.length"
        s *= "$new_column_name.ARRAYELEM($current_index) += $expr_arr.ARRAYELEM(i) ; \n"
    elseif string(func) == "Main.sum"
        s *= "$new_column_name.ARRAYELEM($current_index) +=  $expr_arr.ARRAYELEM(i)  ;\n\n"
    elseif string(func) == "Main.max"
        s *= "if ($new_column_name.ARRAYELEM($current_index) < $expr_arr.ARRAYELEM(i)) \n"
        s *= "$new_column_name.ARRAYELEM($current_index) = $expr_arr.ARRAYELEM(i) ;}\n\n"
    end
    return s
end