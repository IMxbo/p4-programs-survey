/* Copyright 2018-present University of Pennsylvania
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Top-level ingress/egress control flow for a simple packet counter snapshot.
 * Does not include logic for wraparound of counters or snapshotting of channel
 * state.  Also does not include forwarding logic, which can occur in parallel.
 **/


#include "../out/config.p4"
#include "./includes/p4/headers.p4"
#include "./includes/p4/parser.p4"
#include "./includes/p4/ingress.p4"
#include "./includes/p4/egress.p4"
#include "./includes/p4/counter_pkt.p4"
#include "./includes/p4/notify.p4"


/*==========================================
=                Ingress                   =
==========================================*/

control ingress {
    if (ethernet.etherType == ETHERTYPE_IPV4) {
        // Handle a (potentially SS) IPv4 packet
        ciHandleIPv4();
    }
}

control ciHandleIPv4 {
    /*
     * Input: snapshot_header.port_id, ingress_port
     * Output: effective_port, snapshot_feature
     * (in ingress.p4)
     */
	ciInitializeSS();
    /*
     * Input: effective_port
     * Output: current_reading
     * (in counter_pkt.p4)
     */
    apply(tiReadAndUpdateCounter);

    if (snapshot_metadata.snapshot_feature == 0) {
        /*
         * Input: effective_port
         * Output: current_id
         * Postcondition: packet.addIpv4Option(); packet.addSnapshotHeader();
         * (in ingress.p4)
         */
        ciAddHeader();
    } else {
        /*
         * Input: effective_port, snapshot_header.snapshot_id
         * Output: snapshot_case
         * (in ingress.p4)
         */
    	ciSetSnapshotCase();
        /*
         * Input: snapshot_case, snapshot_header.snapshot_id, current_reading
         * Output: current_id
         * Notification: effective_port, snapshot_header.snapshot_id,
         *               current_reading, ingress_global_tstamp
         * (in ingress.p4)
         */
    	ciTakeSnapshot();
    }
    if (snapshot_metadata.snapshot_feature == 2) {
        /*
         * Input: effective_port
         * Postcondition: packet destined for effective_port's egress
         * (in ingress.p4)
         */
        apply(tiForwardInitiation);
    } else {
        /*
         * Input: current_id, effective_port
         * Postcondition: packet set with above parameters
         * (in ingress.p4)
         */
        apply(tiSetSnapHeader);
    }
}


/*==========================================
=                 Egress                   =
==========================================*/

control egress {
    if (standard_metadata.egress_port == CPU_PORT) {
        // If packet is destined for CPU, remove all headers after eth
        // and stuff the last seen notification into the packet.
        // (in egress.p4)
        apply(teFormatForCpu);
    } else if (ethernet.etherType == ETHERTYPE_IPV4) {
        ceHandleIPv4();
    }
}

control ceHandleIPv4 {
    /*
     * Input: egress_port
     * Output: effective_port
     * (in egress.p4)
     */
    apply(teSetEffectivePort);
    /*
     * Input: effective_port
     * Output: current_reading
     * (in counter_pkt.p4)
     */
    apply(teReadAndUpdateCounter);
    /*
     * Input: effective_port, snapshot_header.snapshot_id
     * Output: snapshot_case
     * (in egress.p4)
     */
    ceSetSnapshotCase();
    /*
     * Input: snapshot_case, snapshot_header.snapshot_id, current_reading
     * Output: current_id
     * Notification: effective_port, snapshot_header.snapshot_id,
     *               current_reading, ingress_global_tstamp
     * (in ingress.p4)
     */
    ceTakeSnapshot();
    /*
     * Postcondition: packet either forwarded, dropped, or stripped of its
     * snapshot header.
     * (in egress.p4)
     */
    apply(teFinalizePacket);
}
