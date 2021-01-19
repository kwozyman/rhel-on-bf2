#!/usr/bin/env python

import sys
import time
import logging

from xenalib.XenaSocket import XenaSocket
from xenalib.XenaManager import XenaManager
from xenalib.StatsCSV import write_csv

import scapy.layers.inet as inet
import scapy.utils as utils

logging.basicConfig(level=logging.INFO)

def build_test_packet():
    logging.info("Packet: Using scapy to build the test packet")
    L2 = inet.Ether(src="52:54:00:C6:10:10", dst="04:3f:72:f4:49:44")
    L3 = inet.IP(src="192.168.1.102", dst="192.168.1.101")
    L4 = inet.UDP(sport=1234, dport=1234)
    payload = "X"*22
    packet = L2/L3/L4/payload
    packet_hex = '0x' + bytes(packet).hex()
    # Uncomment below to see the packet in wireshark tool
    # utils.wireshark(packet)

    logging.debug("Packet string: %s", packet_hex)
    return packet_hex

def main():
    # create the test packet
    pkthdr = build_test_packet()
    # create the communication socket
    xsocket = XenaSocket('10.19.188.64')
    if not xsocket.connect():
        sys.exit(-1)

    # create the manager session
    xm = XenaManager(xsocket, 'user1', "xena")

    # add port 0 and configure
    port0 = xm.add_port(4, 0)
    if not port0:
        print("Fail to add port")
        sys.exit(-1)

    port0.set_pause_frames_off()

    port1 = port0

    # add a single stream and configure
    s1_p0 = port0.add_stream(1)
    s1_p0.set_stream_on()
    s1_p0.disable_packet_limit()
    s1_p0.set_rate_fraction()
    s1_p0.set_rate_pps(100)
    s1_p0.set_packet_header(pkthdr)
    s1_p0.set_packet_length_fixed(64, 1518)
    s1_p0.set_packet_payload_incrementing('0x00')
    s1_p0.set_test_payload_id(1)
    s1_p0.set_frame_csum_on()

    # start the traffic
    port0.start_traffic()
    time.sleep(4)

    # fetch stats
    for i in range(0,300):
        port1.grab_all_rx_stats()
        time.sleep(1)

    # stop traffic
    port0.stop_traffic()

    # release resources
    full_stats = port1.dump_all_rx_stats()
    avg_lat = max_lat = min_lat = cnt = 0
    for timestamp in full_stats.keys():
        stats = full_stats[timestamp]
        lat = stats['pr_tpldlatency']['1']['avg']
        max_tmp = stats['pr_tpldlatency']['1']['max']
        min_tmp = stats['pr_tpldlatency']['1']['min']
        max_lat = max_tmp if max_tmp > max_lat else max_lat
        min_lat = min_tmp if min_tmp < min_lat else min_lat
        avg_lat += lat
        cnt += 1

    print("Average latency: %.2f ns" % (avg_lat / cnt))
    print("Max latency: %.2f ns" % (max_lat))
    print("Min latency: %.2f ns" % (min_lat))
    print(stats['pr_tpldlatency']['1'])
    # write_csv("latency.csv", "Latency RX Stats", full_stats)
    del xm
    del xsocket

if __name__ == '__main__':
    main()

