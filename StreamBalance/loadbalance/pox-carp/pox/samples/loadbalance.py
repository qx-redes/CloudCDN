"""
Make a default forwarding and load balance to streaming servers.

This application should be executed in the same network as streaming servers.
"""

from pox.core import core
from pox.lib.util import dpid_to_str
from pox.lib.packet.ethernet import ethernet, ETHER_BROADCAST
from pox.lib.packet.ipv4 import ipv4
from pox.lib.packet.arp import arp
from pox.lib.addresses import IPAddr, EthAddr
from pox.lib.recoco import Timer

from SimpleXMLRPCServer import SimpleXMLRPCServer
import threading
import os
import inspect

import pox.openflow.libopenflow_01 as of

import time

log = core.getLogger()
lock = threading.Lock()

# Global connection necessary to the Timer method (timer_func)
conn = None

FLOW_IDLE_TIMEOUT = 60 * 10
STATS_REQUEST_INTERVAL = 3 

GATEWAY_IP = IPAddr('200.129.39.97')
GATEWAY_MAC = EthAddr('f0:4d:a2:e4:c6:e3')

SERVICE_IP = IPAddr('200.129.39.110')
SERVICE_MAC = EthAddr('00:08:54:e0:c2:35')
SERVICE_PORT_RTSP = 554
SERVICE_PORT_HTTP_LIST = [80,443]

NETWORK_CLOUD = '200.129.39.96/27'

# This method periodically sends a requisition for flow stats on switch. 
def timer_func():
	try:		
		req = of.ofp_stats_request(body=of.ofp_flow_stats_request())
		conn.send(req)
		log.debug("Requesting stats...")
	except:
		log.debug("Failed to send stats request to switch")
	

# This class creates a XML-RPC server on a different thread
class ServerThread(threading.Thread):
    def __init__(self):
        threading.Thread.__init__(self)
        self.timeToQuit = threading.Event()
        self.timeToQuit.clear()      

    def stop(self):    
        self.server.server_close()
        self.timeToQuit.set()

    def _set_instance(self, instance):
    	self.instance = instance

    def run(self):
        print "Running Server"
        self.server = SimpleXMLRPCServer( (str(SERVICE_IP), 8000))
        self.server.register_instance(self.instance)        
        while not self.timeToQuit.isSet():
            self.server.handle_request()

class LoadBalance(object):

	def __init__(self,connection):		
		self.connection = connection
		self.mac = self.connection.eth_addr		
		
		#This dict store a set of active servers (IP -> MAC,PORT).
		self.live_servers = {}

		self.total_bandwidth={}
		
		#This array is used to determine a sequency of servers, necessary to the round-robin policy. Dictionary type has not a sequence.
		self.servers = []
		#This variable is used on round-robin policy to indicate the next server to receive a RTSP request.
		self.serverID = 0
		
		self.connection.addListeners(self)		

		# Send first client requests to the controller.
		fm = of.ofp_flow_mod()
		fm.priority = of.OFP_DEFAULT_PRIORITY
		fm.match.dl_type = ethernet.IP_TYPE
		fm.match.nw_dst = SERVICE_IP
		fm.match.nw_proto = ipv4.TCP_PROTOCOL
		fm.match.tp_dst = SERVICE_PORT_RTSP
		fm.actions.append(of.ofp_action_output(port=of.OFPP_CONTROLLER))
		self.connection.send(fm)	
		for port in SERVICE_PORT_HTTP_LIST
			fm.match.tp_dst = port
			self.connection.send(fm)

		# Let the non-OpenFlow stack handle everything else.
		fm = of.ofp_flow_mod()
		fm.priority = of.OFP_DEFAULT_PRIORITY - 1
		fm.actions.append(of.ofp_action_output(port=of.OFPP_NORMAL))
		self.connection.send(fm)						

	######### Remote methods available via XML-RPC ###########

	# Add a new server to the list
	def addServer(self,ip,mac,port=1):
		lock.acquire()
		try:
			if ip is not None:
				ip = IPAddr(ip)	
				if not self.live_servers.has_key(ip):	
					self.servers.append(ip)
					self.live_servers[ip] = EthAddr(mac),port
					self.total_bandwidth[ip] = 0.0
					response = ">>> New Server Added with IP " + str(ip)
				else:
					response = ">>> Error Adding New Server: IP Already Added"
			else:
				response = ">>> Error Adding New Server: Null IP"			
		finally:
			lock.release()
		log.debug(response)
		return response

	# Remove a server from the list
	def delServer(self,ip):
		lock.acquire()
		try:
			if ip is not None:
				ip = IPAddr(ip)
				if self.live_servers.has_key(ip):
					self.servers.remove(ip)
					del self.live_servers[ip]
					del self.total_bandwidth[ip]
					response = ">>> Server with IP " + str(ip) + " deleted"
					log.debug(response)
				else:
					response = ">>> Error Removing Server: Invalid IP" 
			else:
				response = ">>> Error Removing Server: Null IP"			
		finally:
			lock.release()
		log.debug(response)
		return response

	# Send the server included within the list
	def listServers(self,teste):
		lock.acquire()
		try:
			log.debug(">>> Sending active servers list")
			for server_ip in self.live_servers.keys():			
				log.debug("%s",server_ip)
		finally:
			lock.release()
		return self.servers

	#############################################################
	
	# This method define which server the balancer should send a new RTSP or HTTP requisition
	def _pick_server_rr(self):
		
		if (len(self.servers) == 0):
			return None

		if self.serverID >= (len(self.servers)-1):
			self.serverID = 0
		else:
			self.serverID = self.serverID + 1

		server = self.servers[self.serverID]

		return server		

	# This method define which server the balancer should send a new RTSP or HTTP requisition
	def _pick_server_band(self):
		
		if (len(self.total_bandwidth) == 0):
			return None
		next_server=None
		min_band=-1
		for server in self.total_bandwidth.keys():
			band=self.total_bandwidth[server]
			if min_band == -1:
				next_server=server
				min_band=band
			else:
				if min_band > band:
					next_server=server
					min_band=band	
		return next_server
		
	def _handle_FlowStatsReceived(self,event):		
		
		for server in self.total_bandwidth.keys():
			self.total_bandwidth[server]=0

		for flow in event.stats:
			if flow.duration_sec == 0:
				continue
			server=flow.match.nw_src
	 		if flow.match.nw_proto == ipv4.UDP_PROTOCOL and self.total_bandwidth.has_key(server):
				self.total_bandwidth[server]+=(float(flow.byte_count)/flow.duration_sec)
		return

	def _handle_PacketIn(self,event):		
		
		in_port = event.port
		packet = event.parsed
		buffer_id = event.ofp.buffer_id
		raw_data = event.ofp.data
		
		def drop ():
			if buffer_id is not None:
				# Kill the buffer
				msg = of.ofp_packet_out(data = event.ofp)
				self.connection.send(msg)
			return None

		log.debug("PacketIn received by %s in port %d", dpid_to_str(event.dpid), in_port)
		tcp_packet = packet.find('tcp')		
		ip_packet = packet.find('ipv4')
		
		if tcp_packet is not None:			
			if ip_packet.dstip == SERVICE_IP and packet.dst == SERVICE_MAC:
				if tcp_packet.dstport == SERVICE_PORT_RTSP or tcp_packet.dstport in SERVICE_PORT_HTTP_LIST:	
					
					SERVICE_PORT = tcp_packet.dstport

					if SERVICE_PORT == SERVICE_PORT_RTSP:
						app_proto = "RTSP"
					else:
						app_proto = "HTTP"

					log.debug("---------------------------------------------")
					log.debug("Realizing Load Balance "+app_proto)
					log.debug("TCP information: srcport=%d dstport=%d", tcp_packet.srcport, tcp_packet.dstport)
					log.debug("IP information: srcip=%s dstip=%s", ip_packet.srcip, ip_packet.dstip)					

					# Pick a server for this flow (default: round-robin)
					server_ip = self._pick_server_rr()

					if server_ip is None:
						log.debug("There is not live servers.")
						return drop()

					log.debug(self.live_servers)				
					log.debug("Directing traffic to %s", server_ip)				

					server_mac,server_port = self.live_servers[server_ip]
					client_ip = ip_packet.srcip

					if client_ip.inNetwork(NETWORK_CLOUD):											
						log.debug("Client IP %s is an internal address",client_ip)
						client_mac = packet.src
					else:
						log.debug("Client IP %s is an external address",client_ip)
						client_mac = GATEWAY_MAC

					log.debug("Installing "+app_proto+" flows for %s -> %s (REDIRECT_PORT: %d)",ip_packet.srcip, server_ip, server_port)

					# Creating flow rule: Client -> Server
					msg = of.ofp_flow_mod()
					
					if buffer_id != -1 and buffer_id is not None:
						msg.buffer_id = buffer_id					

					msg.idle_timeout=FLOW_IDLE_TIMEOUT
					msg.hard_timeout=of.OFP_FLOW_PERMANENT
					msg.data=event.ofp
					msg.priority = of.OFP_DEFAULT_PRIORITY + 1					

					msg.match.dl_src = client_mac
					msg.match.dl_dst = SERVICE_MAC
					msg.match.dl_type = ethernet.IP_TYPE
					msg.match.nw_src = client_ip
					msg.match.nw_dst = SERVICE_IP
					msg.match.nw_proto = ipv4.TCP_PROTOCOL
					msg.match.tp_src = tcp_packet.srcport	
					msg.match.tp_dst = SERVICE_PORT
					
					msg.actions.append(of.ofp_action_dl_addr.set_src(SERVICE_MAC))					
					msg.actions.append(of.ofp_action_dl_addr.set_dst(server_mac)) 
					msg.actions.append(of.ofp_action_nw_addr.set_dst(server_ip))
					msg.actions.append(of.ofp_action_output(port=of.OFPP_IN_PORT)) #TODO For multiple interfaces, use server_port

					self.connection.send(msg)

					# Creating flow rule: Server -> Client
					msg = of.ofp_flow_mod()
					
					msg.idle_timeout=FLOW_IDLE_TIMEOUT
					msg.hard_timeout=of.OFP_FLOW_PERMANENT
					msg.priority = of.OFP_DEFAULT_PRIORITY + 1

					msg.match.dl_src = server_mac
					msg.match.dl_dst = SERVICE_MAC
					msg.match.dl_type = ethernet.IP_TYPE
					msg.match.nw_src = server_ip
					msg.match.nw_dst = client_ip
					msg.match.nw_proto = ipv4.TCP_PROTOCOL
					msg.match.tp_src = SERVICE_PORT
					msg.match.tp_dst = tcp_packet.srcport

					msg.actions.append(of.ofp_action_dl_addr.set_src(SERVICE_MAC))
					msg.actions.append(of.ofp_action_nw_addr.set_src(SERVICE_IP))
					msg.actions.append(of.ofp_action_dl_addr.set_dst(client_mac))					
					msg.actions.append(of.ofp_action_output(port = of.OFPP_IN_PORT)) #TODO For multiple interfaces, use server_port

					self.connection.send(msg)
					
					# If application is RTSP-based it is necessary install UDP flow rules for RTP and RTCP protocols. 
					# If client is using a TCP-based RTSP solution, this rules will be deleted automatically according with the FLOW_IDLE_TIMEOUT
					if app_proto=="RTSP":						
						# Creating RTP/RTCP UDP flow rule: Client -> Server
						msg = of.ofp_flow_mod()									

						msg.idle_timeout=FLOW_IDLE_TIMEOUT
						msg.hard_timeout=of.OFP_FLOW_PERMANENT					
						msg.priority = of.OFP_DEFAULT_PRIORITY + 1

						msg.match.dl_src = client_mac
						msg.match.dl_dst = SERVICE_MAC
						msg.match.dl_type = ethernet.IP_TYPE
						msg.match.nw_src = client_ip
						msg.match.nw_dst = SERVICE_IP
						msg.match.nw_proto = ipv4.UDP_PROTOCOL					
						
						msg.actions.append(of.ofp_action_dl_addr.set_src(SERVICE_MAC))					
						msg.actions.append(of.ofp_action_dl_addr.set_dst(server_mac)) 
						msg.actions.append(of.ofp_action_nw_addr.set_dst(server_ip))
						msg.actions.append(of.ofp_action_output(port=of.OFPP_IN_PORT)) #TODO For multiple interfaces, use server_port

						self.connection.send(msg)

						# Creating RTP/RTCP flow rule: Server -> Client

						msg = of.ofp_flow_mod()
						
						msg.idle_timeout=FLOW_IDLE_TIMEOUT
						msg.hard_timeout=of.OFP_FLOW_PERMANENT
						msg.priority = of.OFP_DEFAULT_PRIORITY + 1

						msg.match.dl_src = server_mac
						msg.match.dl_dst = SERVICE_MAC
						msg.match.dl_type = ethernet.IP_TYPE
						msg.match.nw_src = server_ip
						msg.match.nw_dst = client_ip
						msg.match.nw_proto = ipv4.UDP_PROTOCOL					

						msg.actions.append(of.ofp_action_dl_addr.set_src(SERVICE_MAC))
						msg.actions.append(of.ofp_action_nw_addr.set_src(SERVICE_IP))
						msg.actions.append(of.ofp_action_dl_addr.set_dst(client_mac))					
						msg.actions.append(of.ofp_action_output(port = of.OFPP_IN_PORT)) #TODO For multiple interfaces, use server_port

						self.connection.send(msg)								
		else: 
			log.debug("PacketIn not classified!")
		return	

class load_balance (object):
  
	def __init__ (self):
		core.openflow.addListeners(self)

	def _handle_ConnectionUp (self, event):
		
		global conn

		log.debug("Switch %s has come up.", dpid_to_str(event.dpid))
		conn = event.connection
		lb = LoadBalance(conn) 
		
		# Setting a timer to request switch stats (Uncomment if you intend to use a less workload load balance policy)
		#Timer(STATS_REQUEST_INTERVAL, timer_func, recurring=True)
		
		# Creating a XML_RPC Server
		serverThread = ServerThread()
		serverThread._set_instance(lb)
		serverThread.start()

def launch():
	core.registerNew(load_balance)
	


