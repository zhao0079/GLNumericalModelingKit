/*	File: fftwTime2D.cpp 
	
	Description:
		Measure timing of two-dimensional real and complex FFT via FFTW. 
	
	Copyright:
		Copyright (C) 2009 Apple Inc.  All rights reserved.
	
	Disclaimer:
		IMPORTANT:  This Apple software is supplied to you by Apple
		Computer, Inc. ("Apple") in consideration of your agreement to
		the following terms, and your use, installation, modification
		or redistribution of this Apple software constitutes acceptance
		of these terms.  If you do not agree with these terms, please
		do not use, install, modify or redistribute this Apple
		software.

		In consideration of your agreement to abide by the following
		terms, and subject to these terms, Apple grants you a personal,
		non-exclusive license, under Apple’s copyrights in this
		original Apple software (the "Apple Software"), to use,
		reproduce, modify and redistribute the Apple Software, with or
		without modifications, in source and/or binary forms; provided
		that if you redistribute the Apple Software in its entirety and
		without modifications, you must retain this notice and the
		following text and disclaimers in all such redistributions of
		the Apple Software.  Neither the name, trademarks, service
		marks or logos of Apple Computer, Inc. may be used to endorse
		or promote products derived from the Apple Software without
		specific prior written permission from Apple.  Except as
		expressly stated in this notice, no other rights or licenses,
		express or implied, are granted by Apple herein, including but
		not limited to any patent rights that may be infringed by your
		derivative works or by other works in which the Apple Software
		may be incorporated.

		The Apple Software is provided by Apple on an "AS IS" basis.
		APPLE MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING
		WITHOUT LIMITATION THE IMPLIED WARRANTIES OF NON-INFRINGEMENT,
		MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, REGARDING
		THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
		COMBINATION WITH YOUR PRODUCTS.

		IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT,
		INCIDENTAL OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
		TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
		DATA, OR PROFITS; OR BUSINESS INTERRUPTION) ARISING IN ANY WAY
		OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
		OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY
		OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR
		OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF
		SUCH DAMAGE.
*/

/*
 * Created 01/08/2009. 
 * Copyright 2009 by Apple, Inc. 
 */
 
 /* 
  * To build this program you need to have FFTW installed on your system. Download 
  * the source from 
  *
  *     http://www.fftw.org/download.html 
  *
  * Then configure, build, and install both single- and double-precision versions of 
  * the library. The configure step differs depending on your platform, OS release,
  * and whether you're building 32-bit or 64-bit. 
  *
  * The general steps are:
  *
  *    % cd .../fftw-3.1.2
  *    % ./configure <<double-precision arguments>>
  *    % make
  *    % sudo make install
  *    % make clean
  *    % ./configure <<single-precision arguments>>
  *    % make
  *    % sudo make install
  *
  * The configure commands are as follows:
  *
  * PPC 32 bit 
  * ----------
  *		Double:		./configure --enable-threads
  *     Single:		./configure --enable-float --enable-threads --enable-altivec
  *
  * Intel Leopard 32 bit
  * --------------------
  *		Double:		./configure --enable-threads --enable-sse2
  *		Single:		./configure --enable-float --enable-threads --enable-sse 
  *
  * Intel Leopard 64 bit
  * --------------------
  *		Double:		./configure --enable-threads CFLAGS=-m64 --enable-sse2
  *		Single:		./configure --enable-float --enable-threads CFLAGS=-m64 --enable-sse
  *
  * Intel SnowLeopard 32 bit
  * ------------------------
  *		As of SnowLeopard, gcc builds 64-bit by default on a 64-bit machine, so to build 32 bit 
  *		you have to explicitly specify it like this:
  *
  *		Double:		./configure --enable-threads CFLAGS="-O3 -fomit-frame-pointer -malign-double \
  *					 -fstrict-aliasing -ffast-math -march=pentium3 -m32" --enable-sse2
  *		Single:		./configure --enable-float --enable-threads --enable-sse CFLAGS="-O3 \
  *					-fomit-frame-pointer -malign-double -fstrict-aliasing -ffast-math -march=pentium3 -m32"
  *
  * Intel SnowLeopard 64 bit (assuming 64 bit hardware)
  * ---------------------------------------------------
  *		Double:		./configure --enable-threads --enable-sse2
  *		Single:		./configure --enable-float --enable-threads --enable-sse
  */

#include <stdlib.h>
#include <strings.h>
#include <stdio.h>
#include <unistd.h>
#include <math.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libMatrixFFT/fftUtils.h>
#include <libFftwUtils/fftwUtils.h>

#define LOOPS_DEF				10
#define MIN_ROW_SIZE_DEF		32
#define MAX_ROW_SIZE_DEF		(4 * 1024)

static void usage(char **argv)
{
	printf("usage: %s [options]\n", argv[0]);
	printf("Options:\n");
	printf("  -c                 -- complex; default is real\n");
	printf("  -s minRowSpec      -- minimum row size (Complex) or rows (Real); default is %u\n", 
			MIN_ROW_SIZE_DEF);
	printf("  -S maxRowSpec      -- maximum row size (Complex) or rows (Real); default is %u\n", 
			MAX_ROW_SIZE_DEF);
	printf("  -o                 -- out-of-place; default is in-place\n");
	printf("  -f                 -- forward only\n");
	printf("  -u                 -- user time (default is wall time)\n");
	printf("  -l loops           -- default = %u\n", LOOPS_DEF);
	printf("  -T maxThreads      -- default is # of host cores\n");
	printf("  -p                 -- single precision; default per current config\n");
	printf("  -P                 -- double precision; default per current config\n");
	printf("  -e                 -- plan = ESTIMATE (default is %s)\n", FFTW_PLAN_FLAG_DEF_STR);
	printf("  -z                 -- pause for MallocDebug\n");
    printf("  -a                 -- show all results, not just best\n");
	printf("  -v                 -- verbose\n");
	exit(1);
}

typedef struct {
	bool				realSig;			/* true: real; false: complex */
	unsigned			planFlags;
	size_t				numRows;
	size_t				numCols;
	bool				doublePrec;
	bool				wallTime;
	unsigned			loops;
	bool				outOfPlace;
	bool				forwardOnly;
	bool				verbose;
    
    /*
     * bestTime is cumulative fastest (shortest) elapsed time of all 
     * runs at current size. Test updates bestTime if the current run 
     * is faster than the previous festest. 
     * Results are only displayed if lastRun is true (fastest time 
     * displayed) or displayAll is true (display current time regardless).
     */
    double              bestTime;
    bool                lastRun;
    bool                displayAll;
} TestParams;

static int doTest(
	TestParams *tp)
{
	int ourRtn = 0;
	
	unsigned log2Rows;
	unsigned log2Cols;
	if(!fftIsPowerOfTwo(tp->numRows, &log2Rows) ||
	   !fftIsPowerOfTwo(tp->numCols, &log2Cols)) {
		printf("***this test only operates on powers of 2\n");
		return -1;
	}

	size_t totalInSamples = tp->numRows * tp->numCols;
	unsigned log2TotalSamples = log2Rows + log2Cols;
	double ops = (double)totalInSamples * (double)log2TotalSamples;
	if(tp->forwardOnly) { 
		ops *= tp->loops;
	}
	else {
		ops *= (2.0 * tp->loops);
	}
	if(tp->realSig) {
		ops *= 2.5;
	}
	else {
		ops *= 5.0;
	}
	double CTGs;
	
	/* 
	 * Allocate and initialize buffers. 
	 */
	if(tp->verbose) {
		printf("...setting up buffers\n");
	}
	
	/* inputs for real FFTs */
	float  *rBufF = NULL;
	double *rBufD = NULL;
	
	/* inputs for complex FFTs */
	fftwf_complex *cBufInF = NULL;
	fftw_complex  *cBufInD = NULL;

	/* outputs for all forward FFTs - same as input bufs for in-place */
	fftwf_complex *cBufOutF = NULL;
	fftw_complex  *cBufOutD = NULL;
	
	size_t floatSize = tp->doublePrec ? sizeof(double) : sizeof(float);
	size_t complexSize = floatSize << 1;
	
	/* For normalizing/scaling inside the timing loop */
	size_t numInputFloats = totalInSamples;
	double normFactD = 1.0 / (double)totalInSamples;
	float  normFactF = normFactD;
	double *inD;
	float *inF;
	
	double startTime, endTime, elapsedTime;

	if(tp->realSig) {
		/* 
		 * sizes in bytes 
		 * for real FFTs the size of the output row is larger than the input
		 */
		size_t outRowSize = ((tp->numCols >> 1) + 2);		// in floats
		size_t outSize = outRowSize * tp->numRows * complexSize;
		size_t inSize;
		if(tp->outOfPlace) {
			inSize = totalInSamples * floatSize;
		}
		else {
			/* real in-place needs more room for output */
			inSize = outSize;
			numInputFloats = outRowSize * tp->numRows;	// for initializing data
		}
		if(tp->doublePrec) {
			rBufD = (double *)fftw_malloc(inSize);
			if(rBufD == NULL) {
				printf("***malloc failure\n");
				return -1;
			}
		}
		else {
			rBufF = (float *)fftw_malloc(inSize);
			if(rBufF == NULL) {
				printf("***malloc failure\n");
				return -1;
			}
		}	
		if(tp->outOfPlace) {
			if(tp->doublePrec) {
				cBufOutD = (fftw_complex *)fftw_malloc(outSize);
				if(cBufOutD == NULL) {
					printf("***malloc failure\n");
					return -1;
				}
			}
			else {
				cBufOutF = (fftwf_complex *)fftw_malloc(outSize);
				if(cBufOutF == NULL) {
					printf("***malloc failure\n");
					return -1;
				}
			}	
		}
		else {
			cBufOutD = (fftw_complex *)rBufD;
			cBufOutF = (fftwf_complex *)rBufF;
		}
		/* for scaling */
		inD = rBufD;
		inF = rBufF;
	}
	else {
		/* complex */
		numInputFloats <<= 1;
		size_t bufSize = totalInSamples * complexSize;
		if(tp->doublePrec) {
			cBufInD = (fftw_complex *)fftw_malloc(bufSize);
			if(cBufInD == NULL) {
				printf("***malloc failure\n");
				return -1;
			}
		}
		else {
			cBufInF = (fftwf_complex *)fftw_malloc(bufSize);
			if(cBufInF == NULL) {
				printf("***malloc failure\n");
				return -1;
			}
		}
		if(tp->outOfPlace) {
			if(tp->doublePrec) {
				cBufOutD = (fftw_complex *)fftw_malloc(bufSize);
				if(cBufOutD == NULL) {
					printf("***malloc failure\n");
					return -1;
				}
			}
			else {
				cBufOutF = (fftwf_complex *)fftw_malloc(bufSize);
				if(cBufOutF == NULL) {
					printf("***malloc failure\n");
					return -1;
				}
			}	
		}
		else {
			/* in-place */
			cBufOutD = cBufInD;
			cBufOutF = cBufInF;
		}
		/* for scaling */
		inD = (double *)cBufInD;
		inF = (float *)cBufInF;
	}
	/* subsequent errors to errOut: */
	
	if(tp->planFlags != FFTW_ESTIMATE) {
		/* import any accumulated wisdom on this system. */
		fftwGetWisdom(tp->doublePrec);
	}

	/* 
	 * Create plans.
	 */
	if(tp->verbose) {
		printf("...setting up plan\n");
	}
	
	fftw_plan planD      = NULL;
	fftwf_plan planF     = NULL;
	fftw_plan planD_inv  = NULL;
	fftwf_plan planF_inv = NULL;

	if(tp->realSig) {
		if(tp->doublePrec) {
			planD = fftw_plan_dft_r2c_2d(tp->numCols, tp->numRows, rBufD, cBufOutD, tp->planFlags);
			planD_inv = fftw_plan_dft_c2r_2d(tp->numCols, tp->numRows, cBufOutD, rBufD, tp->planFlags);
		}
		else {
			planF = fftwf_plan_dft_r2c_2d(tp->numCols, tp->numRows, rBufF, cBufOutF, tp->planFlags);
			planF_inv = fftwf_plan_dft_c2r_2d(tp->numCols, tp->numRows, cBufOutF, rBufF, tp->planFlags);
		}
	}
	else {
		/* complex */
		if(tp->doublePrec) {
			planD = fftw_plan_dft_2d(tp->numCols, tp->numRows, cBufInD, cBufOutD,
						FFTW_FORWARD, tp->planFlags);
			planD_inv = fftw_plan_dft_2d(tp->numCols, tp->numRows, cBufOutD, cBufInD,
						FFTW_BACKWARD, tp->planFlags);
		}
		else {
			planF = fftwf_plan_dft_2d(tp->numCols, tp->numRows, cBufInF, cBufOutF,
						FFTW_FORWARD, tp->planFlags);
			planF_inv = fftwf_plan_dft_2d(tp->numCols, tp->numRows, cBufOutF, cBufInF,
						FFTW_BACKWARD, tp->planFlags);
		}
	}

	if(tp->doublePrec) {
		if((planD == NULL) || (planD_inv == NULL)) {
			printf("***Error creating plans\n");
			ourRtn = -1;
			goto errOut;
		}
	}
	else {
		if((planF == NULL) || (planF_inv == NULL)) {
			printf("***Error creating plans\n");
			ourRtn = -1;
			goto errOut;
		}
	}
	
	/* Init data - after creating plans, since creating the plans overwrites the data */
	if(tp->doublePrec) {
		double *src = tp->realSig ? rBufD : (double *)cBufInD;
		genRandSignal<double>(src, numInputFloats);
	}
	else {
		float *src = tp->realSig ? rBufF : (float *)cBufInF;
		genRandSignal<float>(src, numInputFloats);
	}
	
	/* Here we go */

	startTime = fftGetTime(tp->wallTime);
	
	for(unsigned loop=0; loop<tp->loops; loop++) {
		if(tp->doublePrec) {
			fftw_execute(planD);
			if(!tp->forwardOnly) {
				fftw_execute(planD_inv);
				vDSP_vsmulD(inD, 1, &normFactD, inD, 1, numInputFloats);
			}
		}
		else {
			fftwf_execute(planF);
			if(!tp->forwardOnly) {
				fftwf_execute(planF_inv);
				vDSP_vsmul(inF, 1, &normFactF, inF, 1, numInputFloats);
			}
		}
	}

	endTime = fftGetTime(tp->wallTime);
	elapsedTime = endTime - startTime;
    
    if(!tp->displayAll) {
        /*
         * Accumulate best time
         */
        if((tp->bestTime == 0.0) ||             // first time thru
           (tp->bestTime > elapsedTime)) {      // new best
            tp->bestTime = elapsedTime;
        }
        if(!tp->lastRun) {
            /* We're done, no display this time thru */
            goto errOut;
        }
        
        /* Last run: display cumulative best */
        elapsedTime = tp->bestTime;
    }

	CTGs = (ops / elapsedTime) / 1.0e+9;
	
	printf("   2^%-2u |  2^%-2u  |   2^%-2u  | %9.3f     | %6.3f\n",
		log2Cols, log2Rows, 
		log2TotalSamples,
		elapsedTime,
		CTGs);

errOut:
	COND_FFTW_FREE(rBufF);
	COND_FFTW_FREE(rBufD);
	COND_FFTW_FREE(cBufInF);
	COND_FFTW_FREE(cBufInD);
	if(tp->outOfPlace) {
		COND_FFTW_FREE(cBufOutF);
		COND_FFTW_FREE(cBufOutD);
	}
	if(planD != NULL) {
		fftw_destroy_plan(planD);
	}
	if(planD_inv != NULL) {
		fftw_destroy_plan(planD_inv);
	}
	if(planF != NULL) {
		fftwf_destroy_plan(planF);
	}
	if(planF_inv != NULL) {
		fftwf_destroy_plan(planF_inv);
	}

	return ourRtn;	
}
	
int main(int argc, char **argv)
{
	const char *fftTypeStr = "Two-dimension real";
	const char *planFlagsStr = FFTW_PLAN_FLAG_DEF_STR;
	char optStr[200];
	TestParams tp;
	bool doPause = false;
	size_t minRowSpec = MIN_ROW_SIZE_DEF;
	size_t maxRowSpec = MAX_ROW_SIZE_DEF;
	int ourRtn = 0;
	unsigned numThreads = 0;			/* 0 here means default of 1 per core */
	char planStr[200];
	
	memset(&tp, 0, sizeof(tp));
	optStr[0] = '\0';
	
	tp.realSig = true;
	tp.planFlags = FFTW_PLAN_FLAG_DEF;
	tp.doublePrec = FFT_DOUBLE_PREC ? true : false;
	tp.wallTime = true;
	tp.loops = LOOPS_DEF;
	
	extern char *optarg;
	int arg;
	while ((arg = getopt(argc, argv, "cs:S:oul:T:pPezvfah")) != -1) {
		switch (arg) {
			case 'c':
				tp.realSig = false;
				fftTypeStr = "Two-dimension complex";
				break;
			case 's':
				minRowSpec = fftParseStringRep(optarg);
				break;
			case 'S':
				maxRowSpec = fftParseStringRep(optarg);
				break;
			case 'v':
				tp.verbose = true;
				break;
			case 'u':
				tp.wallTime = false;
				break;
			case 'l':
				tp.loops = atoi(optarg);
				break;
			case 'o':
				tp.outOfPlace = true;
				break;
			case 'T':
				numThreads = atoi(optarg);
				break;
			case 'p':
				tp.doublePrec = false;
				break;
			case 'P':
				tp.doublePrec = true;
				break;
			case 'e':
				tp.planFlags = FFTW_ESTIMATE;
				planFlagsStr = "ESTIMATE";
				break;
			case 'f':
				tp.forwardOnly = true;
				appendOptStr(optStr, "Forward only");
				break;
			case 'z':
				doPause = true;
				break;
            case 'a':
                tp.displayAll = true;
                break;
			case 'h':
			default:
				usage(argv);
		}
	}
	if(optind != argc) {
		usage(argv);
	}
	if(minRowSpec > maxRowSpec) {
		printf("***maxRowSize must be greater than or equal to minRowSize\n");
		exit(1);
	}
	
	sprintf(planStr, "Plan=%s", planFlagsStr);
	appendOptStr(optStr, planStr);
	if(tp.outOfPlace) {
		appendOptStr(optStr, "Out-of-place");
	}
	else {
		appendOptStr(optStr, "In-place");
	}
	
	if(numThreads == 0) {
		/* Max performance: one thread per core */
		numThreads = numCpuCores();
		if(numThreads == 0) {
			/* numCpuCores() failure, punt */
			numThreads = 1;
		}
	}
	fftPrintTestBanner(fftTypeStr, "FFTW", tp.doublePrec, "Random", 
		optStr, tp.loops, numThreads);
	printf("\n");
	
	printf("  Width | Height | Samples | %s time (s) |  CTGs \n",
		tp.wallTime ? "Wall" : "User");
	printf(" -------+--------+---------+---------------+---------\n");
	
	if(numThreads > 1) {
		if(tp.doublePrec) {
			if(!fftw_init_threads()) {
				printf("***fftw_init_threads returned zero; aborting.\n");
				exit(1);
			}
			fftw_plan_with_nthreads(numThreads);
		}
		else {
			if(!fftwf_init_threads()) {
				printf("***fftwf_init_threads returned zero; aborting.\n");
				exit(1);
			}
			fftwf_plan_with_nthreads(numThreads);
		}
	}
	
	tp.numRows = tp.numCols = minRowSpec;
	
	for(;;) {
        size_t numElts = tp.numRows * tp.numCols;
        if(tp.realSig) {
            /* fftIterationsForSize() takes complex size */
            numElts >> 1;
        }
        unsigned numIter = fftIterationsForSize(numElts);
        
        tp.bestTime = 0.0;
        tp.lastRun = false;
        for(unsigned iter=1; iter<=numIter; iter++) {
            if(iter == numIter) {
                tp.lastRun = true;
            }
            ourRtn = doTest(&tp);
            if(ourRtn) {
                break;
            }
            if(doPause) {
                printf("Pausing at end of loop; CR to continue: ");
                fflush(stdout);
                getchar();
            }
        }
		if(minRowSpec == maxRowSpec) {
			/* infer: user just wants this one run */
			break;
		}
		
		/* Real and complex have different behavior here for compatibility reasons */
		if(tp.realSig) {
			if(tp.numRows == tp.numCols) {
				tp.numCols <<= 1;
			}
			else {
				tp.numRows <<= 1;
			}
			if(tp.numRows > maxRowSpec) {
				break;
			}
		}
		else {
			if(tp.numRows == tp.numCols) {
				tp.numRows <<= 1;
			}
			else {
				tp.numCols <<= 1;
			}
			if(tp.numCols > maxRowSpec) {
				break;
			}
		}
	} 
	
	if(ourRtn == 0) {
		/* save any accumulated wisdom on this system. */
		fftwSaveWisdom(tp.doublePrec);
	}

	return ourRtn;
}
