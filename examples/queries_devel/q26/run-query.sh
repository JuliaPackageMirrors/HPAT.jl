#!/usr/bin/env bash

# Uncomment following line for debuggin
#set -x

# IMPORTANT
# Statically add DAAL libraries because version is not same on all pse nodes
# Add MPI_Wtime() in .cpp before compiling to collect statistics
# HPAT Config 1 =  turn off openmp by commenting enableomp in domain pass, set num_threads in cgen daal to 1 and compile using -daal=sequential remove -qopenmp
# Command to compile Config 1 = mpiicpc -O3 -std=c++11  -I/usr/local/hdf5//include /opt/intel/DAAL/compilers_and_libraries_2016.3.210/linux/daal/lib/intel64_lin/libdaal_core.a   /opt/intel/DAAL/compilers_and_libraries_2016.3.210/linux/daal/lib/intel64_lin/libdaal_sequential.a  -g   -fpic  -o main1 main1.cc -Wl, -Bstatic -ldaal_core -ldaal_sequential -Wl, -Bdynamic -mkl -L/usr/local/hdf5//lib -lhdf5  -lm

# HPAT Config 2 = Default behaviour of HPAT
# Command to Compile = mpiicpc -O3 -std=c++11  -I/usr/local/hdf5//include  -qopenmp /opt/intel/DAAL/compilers_and_libraries_2016.3.210/linux/daal/lib/intel64_lin/libdaal_core.a   /opt/intel/DAAL/compilers_and_libraries_2016.3.210/linux/daal/lib/intel64_lin/libdaal_thread.a -L/opt/intel/DAAL/compilers_and_libraries_2016.3.210/linux/tbb/lib/intel64_lin/gcc4.4/  -g   -fpic  -o main1 main1.cc -Wl, -Bstatic -ldaal_core -ldaal_thread -Wl, -Bdynamic -ltbb -mkl -L/usr/local/hdf5//lib -lhdf5  -lm

# Set DIRs according to your environment
ROOT_DIR=${HOME}
SPARK_DIR=${ROOT_DIR}/spark/
SPARK_QUERY_DIR=${ROOT_DIR}/spark-sql-query-tests/
RESULT_DIR=${ROOT_DIR}/tmp/results/
RESULT_FILE=${RESULT_DIR}/exp-`date +"%Y%m%d%H%M"`-q26.csv
DATASET_DIR=${ROOT_DIR}/tmp/csv/
HPAT_CGEN_BINARY_DIR=${ROOT_DIR}/.julia/v0.4/HPAT/examples/queries_devel/q26/
HPAT_DATAGEN_DIR=${ROOT_DIR}/.julia/v0.4/HPAT/examples/queries_devel/q26/

if [[ ! -d $SPARK_QUERY_DIR ]]; then
    cd $ROOT_DIR
    git clone https://github.com/Wajihulhassan/spark-sql-query-tests.git
fi

cd $SPARK_QUERY_DIR

if [[ "$HOSTNAME" == *PSEPHI* || "$HOSTNAME" == *psephi* ]]; then
    sbt -DproxySet=true -DproxyHost=proxy.jf.intel.com -DproxyPort=911 -v package
else
    sbt -v package
fi

cd -

if [[ ! -d $SPARK_DIR ]]; then
    echo "Download and install spark"
    exit
fi

# TODO generalize this for every query
# wget http://search.maven.org/remotecontent?filepath=org/apache/commons/commons-csv/1.1/commons-csv-1.1.jar -O commons-csv-1.1.jar
# wget https://repo1.maven.org/maven2/com/databricks/spark-csv_2.10/1.4.0/spark-csv_2.10-1.4.0.jar
if [ -f ${RESULT_FILE} ]; then
    rm ${RESULT_FILE}
fi
touch ${RESULT_FILE}

for dataset_factor in "10" "100" "150" "200" "250" "300"; do
    table1_path=$DATASET_DIR/store_sales_sanitized_${dataset_factor}f.csv
    table2_path=$DATASET_DIR/item_sanitized_${dataset_factor}f.csv
    table1_rows=`cat $table1_path | wc -l`
    table2_rows=`cat $table2_path | wc -l`
    if [ ! -f ${table1_path} ] || [ ! -f ${table2_path} ]; then
	echo "Dataset files does not exist !!!"
	exit
    fi
    echo ":D Running Spark"
    ${SPARK_DIR}/bin/spark-submit --conf spark.sql.autoBroadcastJoinThreshold=-1 --master spark://172.16.144.26:7080 --executor-memory 8G --driver-memory 8G  --jars /home/whassan/commons-csv-1.1.jar,/home/whassan/spark-csv_2.10-1.4.0.jar   --class Query26  ~/spark-sql-query-tests/target/scala-2.10/query26_2.10-0.1.jar $table1_path $table2_path &> tmp_spark.txt


    time_q26_spark=`cat tmp_spark.txt  | grep '\*\*\*\*\*\*' | cut -d ' ' -f 6`
    echo "Time took for Query 26[Spark]: "$time_q26_spark
    rm tmp_spark.txt

    echo ":D Copying to hdf5"
    julia ${HPAT_DATAGEN_DIR}/create_data_test_q26.jl 1 "$table1_path" "$table2_path"
    echo ":D Running HPAT Config 1"
    mpirun -hosts psephi07-ib,psephi08-ib,psephi09-ib,psephi10-ib -n 144 -ppn 36 $HPAT_CGEN_BINARY_DIR/main1-config1 2>&1 > tmp_hpat_config1.txt
    time_q26_hpat_config1=`cat tmp_hpat_config1.txt  | grep '\*\*\*\*\*\*' | cut -d ' ' -f 6`
    echo "Time took for Query 26[Hpat]: "$time_q26_hpat_config1
    rm tmp_hpat_config1.txt

    echo ":D Running HPAT  Config 2"
    mpirun -hosts psephi07-ib,psephi08-ib,psephi09-ib,psephi10-ib -n 144 -ppn 36 $HPAT_CGEN_BINARY_DIR/main1-config2 2>&1 > tmp_hpat_config2.txt
    time_q26_hpat_config2=`cat tmp_hpat_config2.txt  | grep '\*\*\*\*\*\*' | cut -d ' ' -f 6`
    echo "Time took for Query 26[Hpat]: "$time_q26_hpat_config2
    rm tmp_hpat_config2.txt

    echo "$dataset_factor,$table1_rows,$table2_rows,$time_q26_spark,$time_q26_hpat_config1,$time_q26_hpat_config2" >>  ${RESULT_FILE}

done