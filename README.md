# assignment_ansible_hdp
## VM used for testing
Tests of playbook were done on a VM provisioned by hdp-bootstrap.sh script from the repo.

## Test results
The only failing step is start of YARN node manager. Failure is probably due to version of jdk (since in Debian 10 can't install Java 8 through `apt`).
Didn't test on CentOS/RHEL, but there is an inclusion based on os_family.

## Hadoop installation file
Archive is downloaded based on `hadoop_version` variable value. (Address can be seen in the role vars).
