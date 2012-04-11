import psutil
import time

def get_network_throughput_avg(sample_time = 1, interface = None):
    """
    Get the average network throughput for a specified `sample_time`, results
    in bytes/s.

    Will show results for all interfaces or for `interface`.

    :returns: Tuple (bytes_out, bytes_in)
    """

    # Fetch network_io_counters, only fetch per inteface if we are checking
    # a specific inteface.
    start_sample = psutil.network_io_counters(interface != None)
    if interface:
        start_sample = start_sample[interface]

    time.sleep(sample_time)

    end_sample = psutil.network_io_counters(interface != None)
    if interface:
        end_sample = end_sample[interface]

    # Calculate differences
    sent_difference = end_sample.bytes_sent - start_sample.bytes_sent
    recv_difference = end_sample.bytes_recv - start_sample.bytes_recv

    # Get actual throughput/s
    sent_throughput = sent_difference / sample_time
    recv_throughput = recv_difference / sample_time

    return (sent_throughput, recv_throughput)
