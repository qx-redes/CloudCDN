/*
* CloudSuite1.0 Benchmark Suite
* Copyright (c) 2011, Parallel Systems Architecture Lab, EPFL
* All rights reserved.
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are met:

*    Redistributions of source code must retain the above copyright
*    notice, this list of conditions and the following disclaimer.
*    Redistributions in binary form must reproduce the above copyright
*    notice, this list of conditions and the following disclaimer in the
*    documentation and/or other materials provided with the distribution.
*    Neither the name of the Parallel Systems Architecture Laboratory, EPFL nor the names of its contributors may be used to endorse or promote products
*    derived from this software without specific prior written permission.

*    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE PARALLEL SYSTEMS ARCHITECTURE LABORATORY, EPFL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*
*Author: Almutaz Adileh
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

static size_t rtp_write(void *ptr, size_t size, size_t nmemb, void *stream){
  printf("Size is: %d\n",size);
  printf("Nmemb is: %d\n",nmemb);
  return size*nmemb;
}

int main(int argc, char *argv[])
{
  CURL  *csession;
  CURLcode res;
  struct curl_slist *custom_msg = NULL;

  char URL[256];
  char temp_URL[256];
  char request[256];
  long rc;
  int port = 48000;
  FILE * protofile = NULL;
  protofile = fopen("Dump","wb");
  if (argc < 2)
  {
      fprintf (stderr, "ERROR: enter a valid URL\n");
      return -1;
  }

  csession = curl_easy_init();

  if (csession == NULL)
      return -1;
  printf("%s\n", argv[1]);  
  sprintf (URL, "%s", argv[1]);
port = atoi(argv[2]);
int timeoutend = atoi(argv[3]);
  
	timeoutend *= 30; //timeoutend holds the correct number of seconds the stream is expected to last

  curl_easy_setopt(csession, CURLOPT_URL, URL);
  curl_easy_setopt(csession, CURLOPT_RTSP_STREAM_URI, URL);
  curl_easy_setopt(csession, CURLOPT_HEADER, 1);

  curl_easy_setopt(csession, CURLOPT_VERBOSE, 1);

  /** retrieve OPTIONS */
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_OPTIONS);
  res = curl_easy_perform(csession);
  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);
  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "OPTIONS Response Code: %ld\n\n", rc);
  }
  else
      return -1;  

  /** send DESCRIBE */  
  custom_msg = curl_slist_append(custom_msg, "Accept: application/x-rtsp-mh, application/rtsl, application/sdp");
  curl_easy_setopt(csession, CURLOPT_RTSPHEADER, custom_msg);
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_DESCRIBE);
  res = curl_easy_perform(csession);

  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);
  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "DESCRIBE Response Code: %ld\n\n", rc);
  }
  else
      return -1;

  /** send SETUP */
  sprintf(temp_URL, "%s/trackID=3", URL);
  printf("%s\n",temp_URL);
  curl_easy_setopt(csession, CURLOPT_RTSP_STREAM_URI, temp_URL);
  sprintf (request, "RTP/AVP/UDP;unicast;client_port=%d-%d", port,port+1);
  //sprintf (request, "RTP/AVP/TCP;unicast"); // SEG FAULT on PLAY
  curl_easy_setopt(csession, CURLOPT_RTSP_TRANSPORT, request);
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_SETUP);
  res = curl_easy_perform(csession);
  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);

  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "SETUP Response Code: %ld\n\n", rc);
  }
  else
      return -1;




  sprintf(temp_URL, "%s/trackID=4", URL);
  printf("%s\n",temp_URL);
  curl_easy_setopt(csession, CURLOPT_RTSP_STREAM_URI, temp_URL);
  sprintf (request, "RTP/AVP/UDP;unicast;client_port=%d-%d", port,port+1);
  //sprintf (request, "RTP/AVP/TCP;interleaved=0-1");
  curl_easy_setopt(csession, CURLOPT_RTSP_TRANSPORT, request);
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_SETUP);
  res = curl_easy_perform(csession);
  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);

  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "SETUP Response Code: %ld\n\n", rc);
  }
  else
      return -1;


  /** send PLAY */
  curl_easy_setopt(csession, CURLOPT_RTSP_STREAM_URI, URL);
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_PLAY);
  fprintf(stderr, "playing...\n\n");
  res = curl_easy_perform(csession);

  if(res != CURLE_OK)
  {
      fprintf(stderr, "PLAY failed: %d (%s)\n\n", res, curl_easy_strerror(res));
      return -1;
  } else {
      res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);
      fprintf(stderr, "PLAY Response Code: %ld\n\n", rc);
  }


//  int timeout = 0;
//  while(timeout < timeoutend ){
  sleep(timeoutend);
/*  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_OPTIONS);
  res = curl_easy_perform(csession);
  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);
  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "OPTIONS Response Code: %ld\n\n", rc);
  }
  else
      return -1;
 
  
  timeout++;

 }
*/
  /** send TEARDOWN */
  curl_easy_setopt(csession, CURLOPT_RTSP_REQUEST, CURL_RTSPREQ_TEARDOWN);
  res = curl_easy_perform(csession);

  res = curl_easy_getinfo(csession, CURLINFO_RESPONSE_CODE, &rc);
  if((res == CURLE_OK) && rc)
  {
      fprintf(stderr, "TEARDOWN Response Code: %ld\n\n", rc);
  }
  else
      return -1;
  
  curl_easy_cleanup(csession);

//  fclose(protofile);   

  return 0;
}
