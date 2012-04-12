import psutil
import time

def _get_network_avg(attributes, sample_time = 1, interface = None):
    """
    Get the average of a network related `attributes` for a
    specified `sample_time`

    Will show results for all interfaces or for `interface`.

    :returns: List (attribute1, attribute2)
    """

    def calculate_average(attribute, old_values, new_values):
        """
        Calculate the average for `attribute` fetching it from
        the old_values/new_values namedtuples.

        :returns: Average value for 1 second for `attribute`
        """

        # Calculate differences
        old_value = getattr(old_values, attribute)
        new_value = getattr(new_values, attribute)

        attr_difference = new_value - old_value

        # Get actual throughput/s
        attr_second = attr_difference / sample_time

        return attr_second

    # Fetch network_io_counters, only fetch per inteface if we are checking
    # a specific inteface.
    start_sample = psutil.network_io_counters(interface != None)
    if interface:
        start_sample = start_sample[interface]

    time.sleep(sample_time)

    end_sample = psutil.network_io_counters(interface != None)
    if interface:
        end_sample = end_sample[interface]

    return [calculate_average(attribute, start_sample, end_sample)
                for attribute in attributes]

def get_network_throughput_avg(sample_time = 1, interface = None):
    """
    Get the average network throughput for a specified `sample_time`, results
    in bytes/s.

    Will show results for all interfaces or for `interface`.

    :returns: Tuple (bytes_out, bytes_in)
    """

    return _get_network_avg(('bytes_sent', 'bytes_recv'), sample_time, interface)
