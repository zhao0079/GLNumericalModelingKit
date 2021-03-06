//
//  GLLinearTransform.m
//  GLNumericalModelingKitCopy
//
//  Created by Jeffrey J. Early on 1/22/13.
//
//

#import "GLLinearTransform.h"
#import "GLEquation.h"
#import "GLDimension.h"
#import "GLVectorVectorOperations.h"
#import "GLVectorScalarOperations.h"
#import "GLUnaryOperations.h"
#import "GLMemoryPool.h"

#import "GLLinearTransformationOperations.h"

#include <mach/mach_time.h>

@interface GLLinearTransform ()
@property(readwrite, assign, nonatomic) NSUInteger nDataPoints;
@property(readwrite, assign, nonatomic) NSUInteger nDataElements;
@property(readwrite, assign, nonatomic) NSUInteger dataBytes;
@end

@implementation GLLinearTransform

/************************************************/
/*		Superclass								*/
/************************************************/

#pragma mark -
#pragma mark Superclass
#pragma mark

- (id) init
{
	[NSException raise: @"BadInitialization" format: @"Cannot initialize GLLinearTransfor with -init method."];
	
	return self;
}

static NSString *GLLinearTransformToDimensionsKey = @"GLLinearTransformToDimensionsKey";
static NSString *GLLinearTransformFromDimensionsKey = @"GLLinearTransformFromDimensionsKey";

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder: coder];
    [coder encodeObject: self.toDimensions forKey: GLLinearTransformToDimensionsKey];
    [coder encodeObject: self.fromDimensions forKey: GLLinearTransformFromDimensionsKey];
}

- (id)initWithCoder:(NSCoder *)coder {
    if ((self=[super initWithCoder: coder])) {
        _toDimensions = [coder decodeObjectForKey: GLLinearTransformToDimensionsKey];
        _fromDimensions = [coder decodeObjectForKey: GLLinearTransformFromDimensionsKey];
        NSMutableArray*array = [NSMutableArray array];
        for (NSUInteger iDim = 0; iDim < self.matrixDescription.nDimensions; iDim++) {
            array[iDim] = @(self.matrixDescription.strides[iDim].matrixFormat);
        }
        _matrixFormats=array;
    }
    return self;
}

@synthesize nDataPoints = _nDataPoints;
@synthesize nDataElements = _nDataElements;
@synthesize dataBytes = _dataBytes;

- (void) dumpToConsole
{
	NSLog(@"%@", [self description]);
}



- (NSString *) graphvisDescription
{
    NSMutableString *extra = [NSMutableString stringWithFormat: @""];
    if (self.name) [extra appendFormat: @"%@:", self.name];
	[extra appendString: self.isComplex ? @"complex" : @"real"];
	if (self.isRealPartZero) [extra appendString:@", zero real part"];
    if (self.isComplex && self.isImaginaryPartZero) [extra appendString:@", zero imaginary part"];
	if (self.isHermitian) [extra appendString: @"hermitian"];
    for (GLDimension *dim in self.fromDimensions) {
        [extra appendFormat: @"\\n%@", dim.graphvisDescription];
    }
    [extra appendString: @"->"];
    for (GLDimension *dim in self.toDimensions) {
        [extra appendFormat: @"\\n%@", dim.graphvisDescription];
    }
    
    return extra;
}

- (NSString *) description
{
    //	return [NSString stringWithFormat: @"%@ <0x%lx> (%@: %lu points)", NSStringFromClass([self class]), (NSUInteger) self, self.name, self.nDataPoints];
	NSMutableString *extra = [NSMutableString stringWithFormat: @""];
	[extra appendString: self.isComplex ? @"complex variable with" : @"real variable with"];
	[extra appendString: self.isRealPartZero ? @" zero real part" : @" nonzero real part"];
	[extra appendString: self.isImaginaryPartZero ? @", zero imaginary part" : @", nonzero imaginary part"];
	[extra appendString: self.isHermitian ? @" and has hermitian symmetry." : @"."];
	
	[extra appendString: @"\n"];
	for (NSUInteger iDim=0; iDim<self.fromDimensions.count; iDim++) {
		[extra appendString: @"\t"];
		if (self.matrixDescription.strides[iDim].matrixFormat == kGLIdentityMatrixFormat) {
            [extra appendFormat: @"kGLIdentityMatrixFormat"];
        } else if (self.matrixDescription.strides[iDim].matrixFormat == kGLDenseMatrixFormat) {
            [extra appendFormat: @"kGLDenseMatrixFormat"];
        } else if (self.matrixDescription.strides[iDim].matrixFormat == kGLDiagonalMatrixFormat) {
            [extra appendFormat: @"kGLDiagonalMatrixFormat"];
        } else if (self.matrixDescription.strides[iDim].matrixFormat == kGLTridiagonalMatrixFormat) {
            [extra appendFormat: @"kGLTridiagonalMatrixFormat"];
        } else if (self.matrixDescription.strides[iDim].matrixFormat == kGLSubdiagonalMatrixFormat) {
            [extra appendFormat: @"kGLSubdiagonalMatrixFormat"];
        } else if (self.matrixDescription.strides[iDim].matrixFormat == kGLSuperdiagonalMatrixFormat) {
            [extra appendFormat: @"kGLSuperdiagonalMatrixFormat"];
        }
		
		[extra appendFormat: @":\t%@\t->\t", [self.fromDimensions[iDim] description]];
		[extra appendFormat: @"%@\n", [self.toDimensions[iDim] description]];
	}
	
    //return [NSString stringWithFormat: @"%@ <0x%lx> (%@: %lu points) %@\n", NSStringFromClass([self class]), (NSUInteger) self, self.name, self.nDataPoints, extra];
    
	return [NSString stringWithFormat: @"%@ <0x%lx> (%@: %lu points) %@\n%@", NSStringFromClass([self class]), (NSUInteger) self, self.name, self.nDataPoints, extra, [self matrixDescriptionString]];
}

- (GLLinearTransform *) rowMajorOrdered {
	if (self.matrixOrder == kGLRowMatrixOrder) {
		return self;
	} else {
		GLVariableOperation *operation = [[GLDataTransposeOperation alloc] initWithLinearTransform: self];
        operation = [self replaceWithExistingOperation: operation];
        return operation.result[0];
	}
}

- (GLLinearTransform *) columnMajorOrdered {
	if (self.matrixOrder == kGLColumnMatrixOrder) {
		return self;
	} else {
		GLVariableOperation *operation = [[GLDataTransposeOperation alloc] initWithLinearTransform: self];
        operation = [self replaceWithExistingOperation: operation];
        return operation.result[0];
	}
}

- (GLLinearTransform *) densified {
	if (self.matrixFormats.count == 1 && ([self.matrixFormats[0] unsignedIntegerValue] == kGLTridiagonalMatrixFormat || [self.matrixFormats[0] unsignedIntegerValue] == kGLDiagonalMatrixFormat)) {
		GLVariableOperation *operation = [[GLDenseMatrixOperation alloc] initWithLinearTransform: self];
        operation = [self replaceWithExistingOperation: operation];
        return operation.result[0];
	} else {
		return self;
	}
}

/************************************************/
/*		Initialization							*/
/************************************************/

#pragma mark -
#pragma mark Initialization
#pragma mark

+ (GLLinearTransform *) transformOfType: (GLDataFormat) dataFormat withFromDimensions: (NSArray *) fromDims toDimensions: (NSArray *) toDims inFormat: (NSArray *) matrixFormats forEquation: (GLEquation *) equation matrix:(GLFloatComplex (^)(NSUInteger *, NSUInteger *)) matrix
{
    return [[self alloc] initTransformOfType: dataFormat withFromDimensions: fromDims toDimensions: toDims inFormat: matrixFormats forEquation: equation matrix:matrix];
}

+ (GLLinearTransform *) transformWithFromDimensions: (NSArray *) fromDims toDimensions: (NSArray *) toDims forEquation: (GLEquation *) equation matrix:(GLFloatComplex (^)(NSUInteger *, NSUInteger *)) matrix {
    return nil;
}

- (GLLinearTransform *) initTransformOfType: (GLDataFormat) dataFormat withFromDimensions: (NSArray *) fromDims toDimensions: (NSArray *) toDims inFormat: (NSArray *) matrixFormats forEquation: (GLEquation *) theEquation matrix:(GLFloatComplex (^)(NSUInteger *, NSUInteger *)) matrix;
{
	return [self initTransformOfType: dataFormat withFromDimensions: fromDims toDimensions: toDims inFormat: matrixFormats withOrdering: kGLRowMatrixOrder forEquation: theEquation matrix: matrix];
}

- (GLLinearTransform *) initTransformOfType: (GLDataFormat) dataFormat withFromDimensions: (NSArray *) fromDims toDimensions: (NSArray *) toDims inFormat: (NSArray *) matrixFormats withOrdering: (GLMatrixOrder) ordering forEquation: (GLEquation *) theEquation matrix:(GLFloatComplex (^)(NSUInteger *, NSUInteger *)) matrix;
{
	if (!theEquation || fromDims.count != toDims.count || fromDims.count != matrixFormats.count) {
		NSLog(@"Attempted to initialize GLLinearTransform without an equation or consistent set of dimensions!!!");
		return nil;
	}
	
	if ((self = [super initWithType: dataFormat withEquation: theEquation])) {
        self.matrixFormats = matrixFormats;
		self.matrixBlock = matrix;
		self.toDimensions = [NSArray arrayWithArray: toDims];
		self.fromDimensions = [NSArray arrayWithArray: fromDims];
		self.matrixOrder = ordering;
		
		// We loop through the dimensions and allocate enough memory for the variable
		// defined on each dimension.
		_nDataPoints = 0;
		BOOL identityMatrix = YES;
		for (NSUInteger iDim=0; iDim < fromDims.count; iDim++)
		{
			GLDimension *fromDim = fromDims[iDim];
			GLDimension *toDim = toDims[iDim];
			GLMatrixFormat matrixFormat = [matrixFormats[iDim] unsignedIntegerValue];
			
			if (_nDataPoints == 0 && matrixFormat != kGLIdentityMatrixFormat) {
				_nDataPoints = 1;
			}
			
			identityMatrix &= matrixFormat == kGLIdentityMatrixFormat;
			
			if ( matrixFormat == kGLIdentityMatrixFormat) {
				_nDataPoints *= 1;
			} else if ( matrixFormat == kGLDenseMatrixFormat) {
				_nDataPoints *= fromDim.nPoints * toDim.nPoints;
			} else if ( matrixFormat == kGLDiagonalMatrixFormat) {
				_nDataPoints *= toDim.nPoints;
			} else if ( matrixFormat == kGLSubdiagonalMatrixFormat) {
				_nDataPoints *= toDim.nPoints;
			} else if ( matrixFormat == kGLSuperdiagonalMatrixFormat) {
				_nDataPoints *= toDim.nPoints;
			} else if ( matrixFormat == kGLTridiagonalMatrixFormat) {
				_nDataPoints *= 3*toDim.nPoints;
			}
			
			if (fromDim.basisFunction == kGLDeltaBasis) {
                self.realSymmetry[iDim] = @(kGLNoSymmetry);
                self.imaginarySymmetry[iDim] = (dataFormat == kGLRealDataFormat ? @(kGLZeroSymmetry) : @(kGLNoSymmetry));
            } else if (fromDim.basisFunction == kGLDiscreteCosineTransformIBasis || fromDim.basisFunction == kGLCosineBasis) {
                self.realSymmetry[iDim] = @(kGLEvenSymmetry);
                self.imaginarySymmetry[iDim] = @(kGLZeroSymmetry);
            } else if (fromDim.basisFunction == kGLDiscreteSineTransformIBasis || fromDim.basisFunction == kGLSineBasis) {
                self.realSymmetry[iDim] = @(kGLOddSymmetry);
                self.imaginarySymmetry[iDim] = @(kGLZeroSymmetry);
            } else if (fromDim.basisFunction == kGLExponentialBasis ) {
                self.realSymmetry[iDim] = @(kGLNoSymmetry);
                self.imaginarySymmetry[iDim] = (dataFormat == kGLRealDataFormat ? @(kGLZeroSymmetry) : @(kGLNoSymmetry));
            }
		}
        
        if (dataFormat == kGLSplitComplexDataFormat || dataFormat == kGLInterleavedComplexDataFormat) {
            _nDataElements = 2*_nDataPoints;
        } else {
			_nDataElements = _nDataPoints;
		}
		
		_dataBytes = _nDataElements*sizeof(GLFloat);
        
        self.matrixDescription = [[GLMatrixDescription alloc] initWithLinearTransform: self];
        
        if (self.matrixBlock) {
			self.data = [GLLinearTransform dataWithFormat: self.matrixDescription fromMatrixBlock: self.matrixBlock];
		}
		
		if (identityMatrix) {
			NSUInteger N = fromDims.count;
			self.matrixBlock = ^( NSUInteger *row, NSUInteger *col ) {
				BOOL onDiagonal = YES;
				for (NSUInteger i=0; i<N; i++) {
					onDiagonal &= row[i]==col[i];
				}
				return (GLFloatComplex) (onDiagonal ? 1 : 0);
			};
		}
	}
	
	return self;
}

+ (transformMatrix) matrixBlockWithFormat: (GLMatrixDescription *) matrixDescription fromData: (NSMutableData *) datain;
{
	NSMutableData *data = [datain copy];
	
	// This block retrieves the matrix value from the correct spot in memory (memIndex), given a particular memory location.
	// The assignment is only dependent on the format and the total number of points.
	GLFloatComplex (^retrieveData)(NSUInteger *, NSUInteger *, GLFloat *, NSUInteger) = [^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger memIndex ) {
		if (matrixDescription.dataFormat == kGLRealDataFormat) {
			return (GLFloatComplex) f[memIndex];
		} else if (matrixDescription.dataFormat == kGLInterleavedComplexDataFormat) {
			return f[memIndex] + I*f[memIndex+matrixDescription.complexStride];
		} else if (matrixDescription.dataFormat == kGLSplitComplexDataFormat) {
			return f[memIndex] + I*f[memIndex+matrixDescription.complexStride];
		} else {
			return (GLFloatComplex) 0.0;
		}
	} copy];
	
	for (NSInteger iDim = matrixDescription.nDimensions-1; iDim >= 0; iDim--)
	{
		GLDataStride stride = matrixDescription.strides[iDim];
		
		// This block encapsulates a loop over the appropriate rows and columns of one dimension pair, given the known data format.
		GLFloatComplex (^loop)(NSUInteger *, NSUInteger *, GLFloat *, NSUInteger);
			
		if (stride.matrixFormat == kGLIdentityMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				return (GLFloatComplex) (row[iDim] == col[iDim] ? retrieveData(row, col, f, index) : 0.0);
			};
		} else if (stride.matrixFormat == kGLDenseMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				return retrieveData(row, col, f, index + row[iDim]*stride.rowStride + col[iDim]*stride.columnStride);
			};
		} else if (stride.matrixFormat == kGLDiagonalMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				if (row[iDim] == col[iDim]) {
					return retrieveData(row, col, f, index + row[iDim]*stride.stride);
				} else {
					return (GLFloatComplex)0.0;
				}
			};
		} else if (stride.matrixFormat == kGLSubdiagonalMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				if (row[iDim] == col[iDim]+1) {
					return retrieveData(row, col, f, index + row[iDim]*stride.stride);
				} else {
					return (GLFloatComplex)0.0;
				}
			};
		} else if (stride.matrixFormat == kGLSuperdiagonalMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				if (row[iDim]+1 == col[iDim]) {
					return retrieveData(row, col, f, index + row[iDim]*stride.stride);
				} else {
					return (GLFloatComplex)0.0;
				}
			};
		} else if (stride.matrixFormat == kGLTridiagonalMatrixFormat) {
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				NSInteger iDiagonal = col[iDim] - row[iDim] + 1;
				if (iDiagonal >= 0 && iDiagonal < 3) {
					return retrieveData(row, col, f, index + iDiagonal*stride.diagonalStride + row[iDim]*stride.stride);
				} else {
					return (GLFloatComplex)0.0;
				}
			};
		}
		
		retrieveData = [loop copy];
	}
	
	transformMatrix matrixBlock = ^(NSUInteger *row, NSUInteger *col) {
		return retrieveData(row, col, (GLFloat *)data.bytes, 0);
	};
	return [matrixBlock copy];
}


+ (NSMutableData *) dataWithFormat: (GLMatrixDescription *) matrixDescription fromMatrixBlock: (transformMatrix) theMatrixBlock
{
	NSMutableData *data = [[GLMemoryPool sharedMemoryPool] dataWithLength: matrixDescription.nBytes];
	[self writeToData: data withFormat: matrixDescription fromMatrixBlock: theMatrixBlock];
	return data;
}

+ (void) writeToData: (NSMutableData *) data withFormat: (GLMatrixDescription *) matrixDescription fromMatrixBlock: (transformMatrix) theMatrixBlock
{
	if (data.length < matrixDescription.nBytes) {
		[NSException raise:@"InsufficientMemory" format:@"Data object has insufficient memory allocated for writing."];
	}
	
	// This block places the matrix value in the correct spot in memory (memIndex), given a particular choice of row and column indices (rows, col).
	// The assignment is only dependent on the format.
	void (^assignData)(NSUInteger *, NSUInteger *, GLFloat *, NSUInteger) = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger memIndex ) {
		GLFloatComplex value = theMatrixBlock(row, col);
		
		if (matrixDescription.dataFormat == kGLRealDataFormat) {
			f[memIndex] = creal(value);
		} else if (matrixDescription.dataFormat == kGLInterleavedComplexDataFormat) {
			f[memIndex] = creal(value);
			f[memIndex+matrixDescription.complexStride] = cimag(value);
		} else if (matrixDescription.dataFormat == kGLSplitComplexDataFormat) {
			f[memIndex] = creal(value);
			f[memIndex+matrixDescription.complexStride] = cimag(value);
		}
	};
	
	void (^assignZeroData)(GLFloat *, NSUInteger) = ^(GLFloat *f, NSUInteger memIndex ) {
		if (matrixDescription.dataFormat == kGLRealDataFormat) {
			f[memIndex] = 0.0;
		} else if (matrixDescription.dataFormat == kGLInterleavedComplexDataFormat) {
			f[memIndex] = 0.0;
			f[memIndex+matrixDescription.complexStride] = 0.0;
		} else if (matrixDescription.dataFormat == kGLSplitComplexDataFormat) {
			f[memIndex] = 0.0;
			f[memIndex+matrixDescription.complexStride] = 0.0;
		}
	};
	
	for (NSInteger iDim = matrixDescription.nDimensions-1; iDim >= 0; iDim--)
	{
		GLDataStride stride = matrixDescription.strides[iDim];
		
		// This block encapsulates a loop over the appropriate rows and columns of one dimension pair, given the known data format.
		void (^loop)( NSUInteger *, NSUInteger *, GLFloat *, NSUInteger );
        
		if (stride.matrixFormat == kGLIdentityMatrixFormat) {
			// We store nothing in this case---so there is no loop. BUT, we still need the row to equal the col.
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
                row[iDim] = 0;
                col[iDim] = 0;
				assignData( row, col, f, index);
			};
		} else if (stride.matrixFormat == kGLDenseMatrixFormat) {
			// Here we loop over ALL possible rows an columns---this matrix is dense.
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				for (NSUInteger i=0; i<stride.nRows; i++) {
					for (NSUInteger j=0; j<stride.nColumns; j++) {
						row[iDim] = i;
						col[iDim] = j;
						
						NSUInteger memIndex = index + i*stride.rowStride + j*stride.columnStride;
						assignData( row, col, f, memIndex);
					}
				}
			};
		} else if (stride.matrixFormat == kGLDiagonalMatrixFormat) {
			// Loop over the diagonal only.
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				for (NSUInteger i=0; i<stride.nDiagonalPoints; i++) {
					row[iDim] = i;
					col[iDim] = i;
					
					NSUInteger memIndex = index + i*stride.stride;
					assignData( row, col, f, memIndex);
				}
			};
		} else if (stride.matrixFormat == kGLSubdiagonalMatrixFormat) {
			// Loop over the sub-diagonal. Assign zero to the first element (which never actually gets used)
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				assignZeroData(f, index + 0*stride.stride);
				for (NSUInteger i=1; i<stride.nDiagonalPoints; i++) {
					row[iDim] = i;
					col[iDim] = i-1;
					
					NSUInteger memIndex = index + i*stride.stride;
					assignData( row, col, f, memIndex);
				}
			};
		} else if (stride.matrixFormat == kGLSuperdiagonalMatrixFormat) {
			// Loop over the super-diagonal. Assign zero to the last element (which never actually gets used)
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				assignZeroData(f, index + (stride.nDiagonalPoints-1)*stride.stride);
				for (NSUInteger i=0; i<stride.nDiagonalPoints-1; i++) {
					row[iDim] = i;
					col[iDim] = i+1;
					
					NSUInteger memIndex = index + i*stride.stride;
					assignData( row, col, f, memIndex);
				}
			};
		} else if (stride.matrixFormat == kGLTridiagonalMatrixFormat) {
			// Loop over the super-diagonal. Assign zero to the last element (which never actually gets used)
			loop = ^( NSUInteger *row, NSUInteger *col, GLFloat *f, NSUInteger index ) {
				assignZeroData(f, index + 0*stride.stride);
				assignZeroData(f, index + (stride.nDiagonalPoints-1)*stride.stride + 2*stride.diagonalStride);
				for (NSUInteger i=1; i<stride.nDiagonalPoints; i++) {
					row[iDim] = i;
					col[iDim] = i-1;
					
					NSUInteger memIndex = index + i*stride.stride;
					assignData( row, col, f, memIndex);
				}
				for (NSUInteger i=0; i<stride.nDiagonalPoints; i++) {
					row[iDim] = i;
					col[iDim] = i;
					
					NSUInteger memIndex = index + i*stride.stride + 1*stride.diagonalStride;
					assignData( row, col, f, memIndex);
				}
				for (NSUInteger i=0; i<stride.nDiagonalPoints-1; i++) {
					row[iDim] = i;
					col[iDim] = i+1;
					
					NSUInteger memIndex = index + i*stride.stride + 2*stride.diagonalStride;
					assignData( row, col, f, memIndex);
				}
			};
		}
		
		assignData = loop;
	}
	
	// And finally, we can now excute the block.
	NSUInteger *rows = malloc(matrixDescription.nDimensions * sizeof(NSUInteger));
	NSUInteger *cols = malloc(matrixDescription.nDimensions * sizeof(NSUInteger));
	assignData( rows, cols, data.mutableBytes, 0);
	free(rows);
	free(cols);
}

- (GLLinearTransform *) copyWithDataType: (GLDataFormat) dataFormat matrixFormat: (NSArray *) matrixFormats ordering: (GLMatrixOrder) ordering
{
	BOOL formatIsTheSame = self.dataFormat == dataFormat;
	formatIsTheSame &= self.matrixOrder == ordering;
	for (NSUInteger i=0; i<self.matrixDescription.nDimensions; i++) {
		formatIsTheSame &= self.matrixDescription.strides[i].matrixFormat == [matrixFormats[i] unsignedIntegerValue];
	}
	
	if (!formatIsTheSame) {
		GLFormatShiftOperation *op = [[GLFormatShiftOperation alloc] initWithLinearTransformation: self dataType: dataFormat matrixFormat: matrixFormats ordering: ordering];
		op = [self replaceWithExistingOperation: op];
		return op.result[0];
	} else {
		return self;
	}
}

/************************************************/
/*		Pre-defined transformations             */
/************************************************/

#pragma mark -
#pragma mark Pre-defined transformations
#pragma mark

+ (void) setLinearTransform: (GLLinearTransform *) diffOp withName: (NSString *) name
{
	[diffOp.equation setLinearTransform: diffOp withName: name];
}

+ (GLLinearTransform *) linearTransformWithName: (NSString *) name forDimensions: (NSArray *) dimensions equation: (GLEquation *) equation
{
	GLLinearTransform *diffOp = [equation linearTransformWithName: name forDimensions: dimensions];
	
	if (!diffOp)
	{
        if ([name isEqualToString: @"harmonicOperator"]) {
            diffOp = [self harmonicOperatorFromDimensions: dimensions forEquation: equation];
        } else {
			NSMutableArray *spatialDimensions = [NSMutableArray arrayWithCapacity: dimensions.count];
			for (GLDimension *dim in dimensions) {
				[spatialDimensions addObject: dim.isFrequencyDomain ? [[GLDimension alloc] initAsDimension:dim transformedToBasis:kGLDeltaBasis strictlyPositive:NO] : dim];
			}
			
            NSMutableArray *derivatives = [NSMutableArray arrayWithCapacity: spatialDimensions.count];
            NSString *reducedString = [name copy];
            for (GLDimension *dim in spatialDimensions)
            {
                NSString *newReducedString = [reducedString stringByReplacingOccurrencesOfString: dim.name withString: @""];
                [derivatives addObject: [NSNumber numberWithUnsignedInteger: reducedString.length - newReducedString.length]];
                reducedString = newReducedString;
            }
            // We check to make sure we can account for the entire string
            if (reducedString.length == 0)
            {
                diffOp = [self differentialOperatorWithDerivatives: derivatives fromDimensions: dimensions forEquation: equation];
            }
        }
		// We check to make sure we can account for the entire string
		if (diffOp)
		{
            diffOp.name = name;
			[self setLinearTransform: diffOp withName: name];
		}
		else
		{
			[NSException raise: @"BadDifferentiationRequest" format: @"Cannot find the differential operator: %@", name];
		}
	}
	
	return diffOp;
}

+ (GLLinearTransform *) discreteTransformFromDimension: (GLDimension *) aDimension toBasis: (GLBasisFunction) aBasis forEquation: (GLEquation *) equation
{
    if (aDimension.basisFunction == kGLDeltaBasis) {
        GLDimension *x=aDimension;
        GLDimension *k;
        
        if (aBasis == kGLExponentialBasis)
        {   // This is the DFT---discrete Fourier transform
            k = [[GLDimension alloc] initAsDimension: x transformedToBasis: aBasis strictlyPositive: NO];
        }
        else if (aBasis == kGLCosineBasis)
        {   // This is the DCT---discrete cosine transform
            k = [[GLDimension alloc] initAsDimension: x transformedToBasis: aBasis strictlyPositive: YES];
        }
        else if (aBasis == kGLSineBasis)
        {   // This is the DST---discrete sine transform
            k = [[GLDimension alloc] initAsDimension: x transformedToBasis: aBasis strictlyPositive: YES];
        }
        else if (aBasis == kGLChebyshevBasis)
        {   // This is the DCT---discrete cosine transform
            k = [[GLDimension alloc] initAsDimension: x transformedToBasis: aBasis strictlyPositive: NO];
        }
        
        return [GLLinearTransform discreteTransformFromDimension: x toDimension: k forEquation: equation];
    }
    else {
        GLDimension *k = aDimension;
        GLDimension *x = [[GLDimension alloc] initAsDimension: k transformedToBasis: kGLDeltaBasis strictlyPositive: NO];
        
        return [GLLinearTransform discreteTransformFromDimension: k toDimension: x forEquation: equation];
    }
    
    return nil;
}

+ (GLLinearTransform *) discreteTransformFromDimension: (GLDimension *) fromDimension toDimension: (GLDimension *) toDimension forEquation: (GLEquation *) equation
{
    if (fromDimension.basisFunction == kGLDeltaBasis) {
        GLDimension *x=fromDimension;
        GLDimension *k=toDimension;
        
        if (toDimension.basisFunction == kGLExponentialBasis)
        {   // This is the DFT---discrete Fourier transform
            GLLinearTransform *dft = [self transformOfType: kGLSplitComplexDataFormat withFromDimensions: @[x] toDimensions: @[k] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: ^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                GLFloat *xVal = (GLFloat *) x.data.bytes;
                GLFloat N = x.nPoints;
                
                GLFloatComplex value = cos(2*M_PI*kVal[row[0]]*xVal[col[0]])/N - I*(sin(2*M_PI*kVal[row[0]]*xVal[col[0]])/N);
                
                return value;
            }];
            
            return dft;
        }
        else if (toDimension.basisFunction == kGLCosineBasis)
        {   // This is the DCT---discrete cosine transform
			transformMatrix matrix;
			
			if (x.isEvenlySampled) { // This creates a much more accurate matrix when we're evenly sampled.
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat k = row[0];
					GLFloat n = col[0];
					
					GLFloatComplex value = cos(M_PI*(n+0.5)*k/x.nPoints)/x.nPoints ;
					
					return value;
				};
			} else {
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat *kVal = (GLFloat *) k.data.bytes;
					GLFloat *xVal = (GLFloat *) x.data.bytes;
					
					GLFloatComplex value = cos(2*M_PI*kVal[row[0]]*xVal[col[0]])/x.nPoints ;
					
					return value;
				};
			}
			
            GLLinearTransform *dct = [self transformOfType: kGLRealDataFormat withFromDimensions: @[x] toDimensions: @[k] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: matrix];
            
            return dct;
        }
        else if (toDimension.basisFunction == kGLSineBasis)
        {   // This is the DST---discrete sine transform
            GLLinearTransform *dst = [self transformOfType: kGLRealDataFormat withFromDimensions: @[x] toDimensions: @[k] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: ^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                GLFloat *xVal = (GLFloat *) x.data.bytes;
                
                GLFloatComplex value = sin(2*M_PI*kVal[row[0]]*xVal[col[0]])/x.nPoints ;
                
                return value;
            }];
            
            return dst;
        }
		else if (toDimension.basisFunction == kGLChebyshevBasis)
		{
			transformMatrix matrix;
			
			if (x.gridType == kGLChebyshevEndpointGrid) { // This creates a much more accurate matrix when we're evenly sampled.
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat k = row[0];
					GLFloat n = col[0];
					
					GLFloatComplex value = (2./(x.nPoints-1.))*cos(M_PI*n*k/(x.nPoints-1.0));
					if ( (row[0]==0 && (col[0] == 0 || col[0] == x.nPoints-1)) || (row[0]==x.nPoints-1 && (col[0] == 0 || col[0] == x.nPoints-1))) {
						value = (GLFloatComplex) (value/4.0);
					} else if (row[0] == 0 || row[0] == x.nPoints-1 ||col[0] == 0 || col[0] == x.nPoints-1) {
						value = (GLFloatComplex) (value/2.0);
					}
					
					// Factor of 2 in order to match the fast transform implementation
					if (row[0] == 0) {
						value = 2*value;
					}
					
					return value;
				};
			} else {
				[NSException raise: @"BadFormat" format:@"Unable to create a Chebyshev matrix for the grid type you requested."];
			}
			
			GLLinearTransform *dct = [self transformOfType: kGLRealDataFormat withFromDimensions: @[x] toDimensions: @[k] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: matrix];
			
			return dct;
		}
    }
    else {
        GLDimension *k = fromDimension;
        GLDimension *x = toDimension;
        if (k.basisFunction == kGLExponentialBasis)
        {   // This is the IDFT---inverse discrete Fourier transform
            GLLinearTransform *idft = [self transformOfType: kGLSplitComplexDataFormat withFromDimensions: @[k] toDimensions: @[x] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: ^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                GLFloat *xVal = (GLFloat *) x.data.bytes;
                
                GLFloatComplex value = cos(2*M_PI*kVal[col[0]]*xVal[row[0]]) + I*sin(2*M_PI*kVal[col[0]]*xVal[row[0]]);
                
                return value;
            }];
            
            return idft;
        }
        else if (k.basisFunction == kGLCosineBasis)
        {   // This is the IDCT---inverse discrete cosine transform
			transformMatrix matrix;
			
			if (x.isEvenlySampled) { // This creates a much more accurate matrix when we're evenly sampled.
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat k = col[0];
					GLFloat n = row[0];
					
					GLFloatComplex value = col[0]==0 ? 1.0 : 2.0*cos(M_PI*(n+0.5)*k/x.nPoints);
					
					return value;
				};
			} else {
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat *kVal = (GLFloat *) k.data.bytes;
					GLFloat *xVal = (GLFloat *) x.data.bytes;
					
					GLFloatComplex value = col[0]==0 ? 1.0 : 2.0*cos(2*M_PI*kVal[col[0]]*xVal[row[0]]);
					
					return value;
				};
			}
			
            GLLinearTransform *idct = [self transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[x] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: matrix];
            
            return idct;
        }
        else if (k.basisFunction == kGLSineBasis)
        {   // This is the IDST---inverse discrete sine transform
            GLLinearTransform *idst = [self transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[x] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: ^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                GLFloat *xVal = (GLFloat *) x.data.bytes;
                
                GLFloatComplex value = col[0]==x.nPoints-1 ? pow(-1.0,x.nPoints) : 2.0*sin(2*M_PI*kVal[col[0]]*xVal[row[0]]);
                
                return value;
            }];
            
            return idst;
        }
		else if (k.basisFunction == kGLChebyshevBasis)
		{   // This is the IDCT---inverse discrete chebyshev transform
			transformMatrix matrix;
			
			if (x.gridType == kGLChebyshevEndpointGrid) {
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat k = col[0];
					GLFloat n = row[0];
					
					GLFloatComplex value = cos(M_PI*n*k/(x.nPoints-1.0));
					
					// Factor of 2 in order to match the fast transform implementation
					if (col[0] == 0) {
						value = value/2.0;
					}
					
					return value;
				};
			} else {
				matrix = ^( NSUInteger *row, NSUInteger *col ) {
					GLFloat *xVal = (GLFloat *) x.data.bytes;
					
					GLFloatComplex value = cos(col[0]*acos((2./x.domainLength)*(xVal[row[0]]-x.domainMin)-1.0));
					
                    // Factor of 2 in order to match the fast transform implementation
                    if (col[0] == 0) {
                        value = value/2.0;
                    }
                    
					return value;
				};
			}
			
			GLLinearTransform *idct = [self transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[x] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix: matrix];
			
			return idct;
		}
    }
	
    [NSException exceptionWithName: @"BadDimension" reason:@"I don't understand the words that are coming out of your mouth." userInfo:nil];
    
    return nil;
}

+ (GLLinearTransform *) differentialOperatorWithDerivatives: (NSUInteger) numDerivs fromDimension: (GLDimension *) k forEquation: (GLEquation *) equation
{
    GLLinearTransform *diff;
    if (numDerivs == 0)
    {
		diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[k] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
            return (GLFloatComplex) (row[0]==col[0] ? 1.0 : 0.0);
        }];
    }
	else if (k.basisFunction == kGLExponentialBasis)
    {
        // i^0=1, i^1=i, i^2=-1, i^3=-i
        GLDataFormat dataFormat = numDerivs % 2 == 0 ? kGLRealDataFormat : kGLSplitComplexDataFormat;
		diff = [GLLinearTransform transformOfType: dataFormat withFromDimensions: @[k] toDimensions: @[k] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
            GLFloat *kVal = (GLFloat *) k.data.bytes;
            return (GLFloatComplex) (row[0]==col[0] ? cpow(I*2*M_PI*kVal[row[0]], numDerivs) : 0.0);
        }];
        diff.isRealPartZero = numDerivs % 2 == 1;
        diff.isImaginaryPartZero = numDerivs % 2 == 0;
	}
    else if (k.basisFunction == kGLCosineBasis)
    {
        if (numDerivs % 2 == 1) {
            GLDimension *transformedDimension = [[GLDimension alloc] initAsDimension: k transformedToBasis: kGLSineBasis strictlyPositive: YES];
            GLFloat sign = (numDerivs-1)/2 % 2 ? 1. : -1.;
            diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[transformedDimension] inFormat: @[@(kGLSuperdiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                return (GLFloatComplex) (row[0]+1==col[0] ? sign*pow(2*M_PI*kVal[row[0]+1], numDerivs) : 0.0);
            }];
        } else {
            GLFloat sign = numDerivs/2 % 2 ? -1. : 1.;
            diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[k] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                return (GLFloatComplex) (row[0]==col[0] ? sign*pow(2*M_PI*kVal[row[0]], numDerivs) : 0.0);
            }];
        }
	}
    else if (k.basisFunction == kGLSineBasis)
    {
        if (numDerivs % 2 == 1) {
            GLDimension *transformedDimension = [[GLDimension alloc] initAsDimension: k transformedToBasis: kGLCosineBasis strictlyPositive: YES];
            GLFloat sign = (numDerivs-1)/2 % 2 ? -1. : 1.;
            diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[transformedDimension] inFormat: @[@(kGLSubdiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                return (GLFloatComplex) (row[0]-1==col[0] ? sign*pow(2*M_PI*kVal[row[0]-1], numDerivs) : 0.0);
            }];
        } else {
            GLFloat sign = numDerivs/2 % 2 ? -1. : 1.;
            diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[k] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
                GLFloat *kVal = (GLFloat *) k.data.bytes;
                return (GLFloatComplex) (row[0]==col[0] ? sign*pow(2*M_PI*kVal[row[0]], numDerivs) : 0.0);
            }];
        }
	} else if (k.basisFunction == kGLChebyshevBasis)
    {
        if (numDerivs > 1) [NSException exceptionWithName: @"NotYetImplemented" reason:@"Chebyshev derivatives greater than 1 are not yet implemented. See comments." userInfo:nil];
        
        // Matlab script for higher order derivatives here: http://dip.sun.ac.za/~weideman/research/differ.html
		diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[k] toDimensions: @[k] inFormat: @[@(kGLDenseMatrixFormat)] forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
            GLFloat *kVal = (GLFloat *) k.data.bytes;
            return (GLFloatComplex) (  (col[0] >= row[0]+1 && (row[0]+col[0])%2==1)  ? 2.*kVal[col[0]] : 0.0);
        }];
	} else if (k.basisFunction == kGLDeltaBasis)
	{
		diff = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: numDerivs leftBC: kGLNeumannBoundaryCondition rightBC:kGLNeumannBoundaryCondition bandwidth: floor(numDerivs/2) + 1 fromDimension:k forEquation: equation];
	}
	else {
        [NSException raise: @"NotYetImplemented" format:@"Derivatives for that basis are not yet implemented"];
    }
    
    return diff;
}

+ (GLLinearTransform *) differentialOperatorWithDerivatives: (NSArray *) numDerivs fromDimensions: (NSArray *) dimensions forEquation: (GLEquation *) equation
{
    NSMutableArray *linearTransformations = [NSMutableArray array];

    for (NSUInteger i=0; i<dimensions.count; i++) {
        GLLinearTransform *diffOp = [self differentialOperatorWithDerivatives: [numDerivs[i] unsignedIntegerValue] fromDimension: dimensions[i] forEquation:equation];
        linearTransformations[i] = diffOp;
    }
	
    return [self tensorProduct: linearTransformations];
}

+ (GLLinearTransform *) tensorProduct: (NSArray *) linearTransformations {
	GLTensorProductOperation *operation = [[GLTensorProductOperation alloc] initWithLinearTransformations: linearTransformations];
	return operation.result[0];
}

+ (GLLinearTransform *) harmonicOperatorOfOrder: (NSUInteger) order fromDimensions: (NSArray *) dimensions forEquation: (GLEquation *) equation;
{
	NSMutableArray *zeros = [NSMutableArray array];
	for (NSUInteger i=0; i<dimensions.count; i++) {
		[zeros addObject: @0];
	}
	
	// Build the operators
	GLLinearTransform *harmonicOperator=nil;;
	for (NSUInteger i=0; i<dimensions.count; i++) {
		NSMutableArray *deriv = [zeros mutableCopy];
		deriv[i] = @2;
		if (harmonicOperator) {
			harmonicOperator = (GLLinearTransform *) [harmonicOperator plus: [GLLinearTransform differentialOperatorWithDerivatives: deriv fromDimensions: dimensions forEquation: equation]];
		} else {
			harmonicOperator = [GLLinearTransform differentialOperatorWithDerivatives: deriv fromDimensions: dimensions forEquation: equation];
		}
	}
	
	for (NSUInteger i=1; i<order; i++) {
		harmonicOperator = [harmonicOperator matrixMultiply: harmonicOperator];
	}
	
	[equation solveForVariable: harmonicOperator waitUntilFinished: YES];
		
    harmonicOperator.name = [NSString stringWithFormat: @"nabla^%lu", order];
	return harmonicOperator;
}

+ (GLLinearTransform *) harmonicOperatorFromDimensions: (NSArray *) dimensions forEquation: (GLEquation *) equation
{
	return [GLLinearTransform harmonicOperatorOfOrder: 1 fromDimensions: dimensions forEquation: equation];
}

// The SVV operator is a filter which multiplies the the toDimensions, and gives the toDimensions back.
+ (GLLinearTransform *) spectralVanishingViscosityFilterWithDimensions: (NSArray *) dimensions scaledForAntialiasing: (BOOL) isAntialiasing forEquation: (GLEquation *) equation;
{
	GLFloat minNyquist = HUGE_VAL;
	GLFloat minSampleInterval = HUGE_VAL;
	NSMutableArray *matrixFormat = [NSMutableArray arrayWithCapacity: dimensions.count];
	
	for (GLDimension *dim in dimensions) {
		GLFloat nyquist = dim.domainMin + dim.domainLength;
		if (nyquist < minNyquist) {
			minNyquist = nyquist;
			minSampleInterval = dim.sampleInterval;
		}
		[matrixFormat addObject: @(kGLDiagonalMatrixFormat)];
	}
	
	if (isAntialiasing) {
		minNyquist = 2*minNyquist/3;
	}
	
	// Note that the 'minSampleInterval' is deltaK (not deltaX)
	GLFloat wavenumberCutoff = minSampleInterval * pow(minNyquist/minSampleInterval, 0.75);
	
	NSUInteger nDims = dimensions.count;
	GLLinearTransform *filter = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: dimensions toDimensions: dimensions inFormat: matrixFormat forEquation: equation matrix:^( NSUInteger *row, NSUInteger *col ) {
		// Bail as soon as we see that we're not on the diagonal
		for (NSUInteger i=0; i<nDims; i++) {
			if (row[i]!=col[i]) return (GLFloatComplex) 0.0;
		}
		
		// Okay, we're on the diagonal, so now compute k
		GLDimension *dim = dimensions[0];
		GLFloat k = [dim valueAtIndex: row[0]] * [dim valueAtIndex: row[0]];
		for (NSUInteger i=1; i<nDims; i++) {
			dim = dimensions[i];
			k +=[dim valueAtIndex: row[i]] * [dim valueAtIndex: row[i]];
		}
		k = sqrt(k);
		
		if (k < wavenumberCutoff) {
			return (GLFloatComplex) 0.0;
		} else if ( k > minNyquist) {
			return (GLFloatComplex) 1.0;
		} else {
			return (GLFloatComplex) exp(-pow((k-minNyquist)/(k-wavenumberCutoff),2.0));
		}
	}];
	
	return filter;
}

+ (GLLinearTransform *) linearTransformFromFunction: (GLFunction *) aFunction
{
    GLDiagonalTransformCreationOperation *op = [[GLDiagonalTransformCreationOperation alloc] initWithFunction: aFunction];
    return op.result[0];
}

- (void) setVariableAlongDiagonal: (GLFunction *) diagonalVariable
{
    if (self.matrixDescription.nDimensions == 1)
    {
        if (self.matrixDescription.strides[0].matrixFormat == kGLDenseMatrixFormat) {
            
            GLFloat *f = self.pointerValue;
            GLFloat *a = diagonalVariable.pointerValue;
            
            NSUInteger rowStride = self.matrixDescription.strides[0].rowStride;
            NSUInteger columnStride = self.matrixDescription.strides[0].columnStride;
            
            for ( NSUInteger i=0; i<self.matrixDescription.strides[0].nRows; i++) {
                for ( NSUInteger j=0; j<self.matrixDescription.strides[0].nColumns; j++) {
                    if (i==j) {
                        f[i*rowStride + j*columnStride] = a[j];
                    } else {
                        f[i*rowStride + j*columnStride] = 0.0;
                    }
                }
            }
            
        }
    }
}

- (void) setVariablesAlongTridiagonal: (NSArray *) tridiagonalVariables
{
    NSUInteger triIndex = NSNotFound;
	NSUInteger firstNonTriIndex = NSNotFound;
	NSUInteger numTriIndices = 0;
    for ( NSNumber *num in self.matrixFormats) {
        if ([num unsignedIntegerValue] == kGLTridiagonalMatrixFormat) {
            triIndex = [self.matrixFormats indexOfObject: num];
			numTriIndices++;
        } else if ([num unsignedIntegerValue] != kGLIdentityMatrixFormat && firstNonTriIndex == NSNotFound ) {
			firstNonTriIndex = [self.matrixFormats indexOfObject: num];
		}
    }
    
    GLFloat *a = [tridiagonalVariables[0] pointerValue];
    GLFloat *b = [tridiagonalVariables[1] pointerValue];
    GLFloat *c = [tridiagonalVariables[2] pointerValue];
    
    GLFloat *d = self.pointerValue;
    NSUInteger elementStride = self.matrixDescription.strides[triIndex].stride;
    NSUInteger diagonalStride = self.matrixDescription.strides[triIndex].diagonalStride;
    NSUInteger m,n;
    for ( NSUInteger i=0; i<[tridiagonalVariables[0] nDataPoints]; i++) {
        m = i%diagonalStride;
        n = i/diagonalStride;
        d[ (3*n+0)*diagonalStride + m*elementStride] = a[i];
        d[ (3*n+1)*diagonalStride + m*elementStride] = b[i];
        d[ (3*n+2)*diagonalStride + m*elementStride] = c[i];
    }
}

/************************************************/
/*		Dimensionality							*/
/************************************************/

#pragma mark -
#pragma mark Dimensionality
#pragma mark

- (BOOL) isHermitian {
	if (self.hermitianDimension) {
		NSUInteger i = [self.fromDimensions indexOfObject: self.hermitianDimension];
		return ( ([self.realSymmetry[i] unsignedIntegerValue] == kGLEvenSymmetry || self.isRealPartZero) && ([self.imaginarySymmetry[i] unsignedIntegerValue] == kGLOddSymmetry || self.isImaginaryPartZero) );
	}
	return NO;
}

- (NSUInteger) rank {
	return 2;
}

- (GLLinearTransform *) expandedWithFromDimensions: (NSArray *) fromDims toDimensions: (NSArray *) toDims
{
	// The existing dimension have to be in the same order.
	GLVariableOperation *operation = [[GLExpandMatrixDimensionsOperation alloc] initWithLinearTransformation: self fromDimensions: fromDims toDimensions: toDims];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

- (GLLinearTransform *) reducedFromDimensions: (NSString *) fromString toDimension: (NSString *) toString
{
	GLVariableOperation *operation = [[GLReduceMatrixDimensionsOperation alloc] initWithLinearTransformation: self fromDimensionsIndexString: fromString toDimensionsIndexString:toString];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

/************************************************/
/*		Operations								*/
/************************************************/

#pragma mark -
#pragma mark Operations
#pragma mark

- (GLFunction *) transform: (GLFunction *) x
{
	NSUInteger numIdentityIndices = 0;
	NSUInteger numDiagonalIndices = 0;
	NSUInteger numSubDiagonalIndices = 0;
	NSUInteger numSuperDiagonalIndices = 0;
	NSUInteger numTriIndices = 0;
	NSUInteger numDenseIndices = 0;
	for ( NSNumber *num in self.matrixFormats ) {
        if ([num unsignedIntegerValue] == kGLIdentityMatrixFormat) {
			numIdentityIndices++;
        } else if ([num unsignedIntegerValue] == kGLDiagonalMatrixFormat) {
			numDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSubdiagonalMatrixFormat) {
			numSubDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSuperdiagonalMatrixFormat) {
			numSuperDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLTridiagonalMatrixFormat) {
			numTriIndices++;
        } else if ([num unsignedIntegerValue] == kGLDenseMatrixFormat) {
			numDenseIndices++;
        }
    }
		
	if (numDenseIndices == 0 && numSubDiagonalIndices == 0 && numSuperDiagonalIndices == 0 && numTriIndices == 1) {
		// Tridiagonal matrix transformations.
		GLTriadiagonalTransformOperation *operation = [[GLTriadiagonalTransformOperation alloc] initWithLinearTransformation: self function: x];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	} else if (numDenseIndices == 1 && numSubDiagonalIndices == 0 && numSuperDiagonalIndices == 0 && numTriIndices == 0) {
		// Dense matrix transformations.
		GLDenseMatrixTransformOperation *operation = [[GLDenseMatrixTransformOperation alloc] initWithLinearTransformation: self function: x];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	}  else if (numDenseIndices == 0 && numIdentityIndices == 0 && numSubDiagonalIndices == 0 && numSuperDiagonalIndices == 0 && numTriIndices == 0 && numIdentityIndices == 0) {
		// Diagonal matrix transformation
		GLMultiplicationOperation *operation = [[GLMultiplicationOperation alloc] initWithFirstOperand: self secondOperand: x];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	}  else if (numDenseIndices == 0 && numIdentityIndices == 0 && numTriIndices == 0 && numIdentityIndices == 0) {
		// General diagonal matrix transformation
		GLSingleDiagonalTransformOperation *operation = [[GLSingleDiagonalTransformOperation alloc] initWithLinearTransformation: self function: x];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	}
	
	NSString *descrip = [NSString stringWithFormat: @"No algorithm implemented to solve problem. This matrix contains (identity, diagonal, sub-diagonal, super-diagonal, tri-diagonal, dense)=(%lu,%lu,%lu,%lu,%lu,%lu) indices", numIdentityIndices, numDiagonalIndices,numSubDiagonalIndices, numSuperDiagonalIndices, numTriIndices, numDenseIndices];
	[NSException raise:@"BadFormat" format: @"%@", descrip];
	
	return nil;
}

- (GLFunction *) solve: (GLFunction *) b
{
	NSUInteger numIdentityIndices = 0;
	NSUInteger numDiagonalIndices = 0;
	NSUInteger numSubDiagonalIndices = 0;
	NSUInteger numSuperDiagonalIndices = 0;
	NSUInteger numTriIndices = 0;
	NSUInteger numDenseIndices = 0;
	for ( NSNumber *num in self.matrixFormats ) {
        if ([num unsignedIntegerValue] == kGLIdentityMatrixFormat) {
			numIdentityIndices++;
        } else if ([num unsignedIntegerValue] == kGLDiagonalMatrixFormat) {
			numDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSubdiagonalMatrixFormat) {
			numSubDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSuperdiagonalMatrixFormat) {
			numSuperDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLTridiagonalMatrixFormat) {
			numTriIndices++;
        } else if ([num unsignedIntegerValue] == kGLDenseMatrixFormat) {
			numDenseIndices++;
        }
    }
	
	if ( numIdentityIndices && !numDiagonalIndices && !numTriIndices && !numDenseIndices )
	{	// Trivially solution.
		return b;
	}
	else if ( numDiagonalIndices && !numTriIndices && !numDenseIndices )
	{	// Diagonal only
		
	}
	else if ( numTriIndices == 1 && !numDenseIndices )
	{	// A single tridiagonal dimension
		GLTriadiagonalSolverOperation *operation = [[GLTriadiagonalSolverOperation alloc] initWithLinearTransformation: self function: b];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	}
	else if ( !numTriIndices && numDenseIndices == 1 )
	{	// A single dense dimension
		GLDenseMatrixSolver *operation = [[GLDenseMatrixSolver alloc] initWithLinearTransformation: self function: b];
		operation = [self replaceWithExistingOperation: operation];
		return operation.result[0];
	}
	
	NSString *descrip = [NSString stringWithFormat: @"No algorithm implemented to solve problem. This matrix contains (identity, diagonal, sub-diagonal, super-diagonal, tri-diagonal, dense)=(%lu,%lu,%lu,%lu,%lu,%lu) indices", numIdentityIndices, numDiagonalIndices,numSubDiagonalIndices, numSuperDiagonalIndices, numTriIndices, numDenseIndices];
	[NSException exceptionWithName: @"BadFormat" reason:descrip userInfo:nil];
	
	return nil;
}

- (GLLinearTransform *) matrixMultiply: (GLLinearTransform *) otherVariable
{
	// Not very smart yet---we only know how to matrix multiply diagonal matrices (of any dimension) or 1D dense matrices.
	GLLinearTransform *A = self;
	GLLinearTransform *B = otherVariable;
	
	if ( ![A.fromDimensions isEqualToArray: B.toDimensions] ) {
		[NSException raise: @"DimensionsNotEqualException" format: @"When multiplying two matrices, the fromDimensions of A, must equal the toDimensions of B."];
	}
	
	NSUInteger numDiagonalIndicesMatrixA = 0;
	NSUInteger numDensifiableIndicesMatrixA = 0;
	NSUInteger densifiableIndexMatrixA = NSNotFound;
	
	NSUInteger numDiagonalIndicesMatrixB = 0;
	NSUInteger numDensifiableIndicesMatrixB = 0;
	NSUInteger densifiableIndexMatrixB = NSNotFound;
	
	for ( NSUInteger index=0; index<A.fromDimensions.count; index++ ) {
		GLMatrixFormat formatA = [A.matrixFormats[index] unsignedIntegerValue];
		GLMatrixFormat formatB = [B.matrixFormats[index] unsignedIntegerValue];
		
		if (formatA == kGLDiagonalMatrixFormat) {
			numDiagonalIndicesMatrixA++;
		} else if (formatA == kGLSubdiagonalMatrixFormat || formatA == kGLSuperdiagonalMatrixFormat || formatA == kGLTridiagonalMatrixFormat || formatA == kGLDenseMatrixFormat) {
			numDensifiableIndicesMatrixA++;
			densifiableIndexMatrixA = index;
		}
		
        if (formatB == kGLDiagonalMatrixFormat) {
			numDiagonalIndicesMatrixB++;
		} else if (formatB == kGLSubdiagonalMatrixFormat || formatB == kGLSuperdiagonalMatrixFormat || formatB == kGLTridiagonalMatrixFormat || formatB == kGLDenseMatrixFormat) {
			numDensifiableIndicesMatrixB++;
			densifiableIndexMatrixB = index;
		}
    }
		
	GLVariableOperation *operation;
	if (numDiagonalIndicesMatrixA == A.fromDimensions.count && [A.matrixDescription isEqualToMatrixDescription: B.matrixDescription]) {
		operation = [[GLMultiplicationOperation alloc] initWithFirstOperand: A secondOperand: B];
	} else if ( (numDensifiableIndicesMatrixA <= 1 || numDensifiableIndicesMatrixB <= 1) && (densifiableIndexMatrixA == densifiableIndexMatrixB || densifiableIndexMatrixA == NSNotFound || densifiableIndexMatrixB == NSNotFound ) ) {
		NSUInteger index = densifiableIndexMatrixA == NSNotFound ? densifiableIndexMatrixB : densifiableIndexMatrixA;
		if (index == NSNotFound) {
			[NSException raise:@"StupidMatrixMultiplication" format: @"This is possible, but what's the logic?"];
		}
		NSMutableArray *newMatrixAFormats = [A.matrixFormats mutableCopy];
		NSMutableArray *newMatrixBFormats = [B.matrixFormats mutableCopy];
		newMatrixAFormats[index] = @(kGLDenseMatrixFormat);
		newMatrixBFormats[index] = @(kGLDenseMatrixFormat);
		A = [A copyWithDataType: A.dataFormat matrixFormat: newMatrixAFormats ordering:kGLRowMatrixOrder];
		B = [B copyWithDataType: B.dataFormat matrixFormat: newMatrixBFormats ordering:kGLRowMatrixOrder];
		operation = [[GLMatrixMatrixMultiplicationOperation alloc] initWithFirstOperand: A secondOperand: B];
	} else {
		[NSException raise: @"StupidMatrixMultiplication" format: @"You have requested the matrix multiplicatin of two matrices, but we only support diagonal matrices and 1D dense matrices."];
	}
	
    operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

- (GLLinearTransform *) inverse
{
    NSUInteger numIdentityIndices = 0;
	NSUInteger numDiagonalIndices = 0;
	NSUInteger numSubDiagonalIndices = 0;
	NSUInteger numSuperDiagonalIndices = 0;
	NSUInteger numTriIndices = 0;
	NSUInteger numDenseIndices = 0;
	for ( NSNumber *num in self.matrixFormats ) {
        if ([num unsignedIntegerValue] == kGLIdentityMatrixFormat) {
			numIdentityIndices++;
        } else if ([num unsignedIntegerValue] == kGLDiagonalMatrixFormat) {
			numDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSubdiagonalMatrixFormat) {
			numSubDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLSuperdiagonalMatrixFormat) {
			numSuperDiagonalIndices++;
        } else if ([num unsignedIntegerValue] == kGLTridiagonalMatrixFormat) {
			numTriIndices++;
        } else if ([num unsignedIntegerValue] == kGLDenseMatrixFormat) {
			numDenseIndices++;
        }
    }
    
    GLVariableOperation *operation;
    if (numIdentityIndices == 0 && numDiagonalIndices !=0 && numSubDiagonalIndices == 0  && numSuperDiagonalIndices == 0 && numTriIndices == 0 && numDenseIndices == 0 ) {
        operation = [[GLScalarDivideOperation alloc] initWithVectorOperand: self scalarOperand: 1.0];
    }
    else if (numIdentityIndices == 0 && numDiagonalIndices ==0 && numSubDiagonalIndices == 0  && numSuperDiagonalIndices == 0 && numTriIndices == 0 && numDenseIndices != 0) {
        operation = [[GLMatrixInversionOperation alloc] initWithLinearTransformation: self];
    }
    
    operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

- (NSArray *) eigensystem
{
	GLVariableOperation *operation = [[GLMatrixEigensystemOperation alloc] initWithLinearTransformation: self];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result;
}

- (NSArray *) eigensystemWithOrder: (NSComparisonResult) sortOrder
{
	GLVariableOperation *operation = [[GLMatrixEigensystemOperation alloc] initWithLinearTransformation: self sort: sortOrder];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result;
}

- (NSArray *) generalizedEigensystemWith: (GLLinearTransform *) B
{
	GLVariableOperation *operation = [[GLGeneralizedMatrixEigensystemOperation alloc] initWithFirstOperand: self secondOperand: B];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result;
}

- (GLLinearTransform *) normalizeWithScalar: (GLFloat) aScalar acrossDimensions: (NSUInteger) dimIndex
{
	GLVariableOperation *operation = [[GLMatrixNormalizationOperation alloc] initWithLinearTransformation: self normalizationConstant: aScalar dimensionIndex: dimIndex];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

- (GLLinearTransform *) normalizeWithFunction: (GLFunction *) aFunction
{
	GLVariableOperation *operation = [[GLMatrixNormalizationOperation alloc] initWithLinearTransformation: self normalizationFunction: aFunction];
	operation = [self replaceWithExistingOperation: operation];
	return operation.result[0];
}

/************************************************/
/*		Finite Differencing						*/
/************************************************/

#pragma mark -
#pragma mark Finite Differencing
#pragma mark

// http://www.scholarpedia.org/article/Finite_difference_method

// z contains the position where the approximation is to be accurate
// x is an array of length n of grid point positions
// m the highest derivative we need to find the weights for
// c an array of length (m+1)*n containing the weights of the derivative (row) at a grid position (column)
// n is the length of the grid point position array
// x and c must be pre-allocated.
void weights( GLFloat z, GLFloat *x, NSUInteger m, GLFloat *c, NSUInteger n )
{
	vGL_vclr(c,1,(m+1)*n);
    GLFloat c1=1;
    GLFloat c4=x[0]-z;
    c[0*n+0] = 1;
    for (NSUInteger i=1; i<n; i++)
    {
        NSUInteger mn = i<m?i:m;
        GLFloat c2=1;
        GLFloat c5=c4;
        c4=x[i]-z;
        
        for (NSUInteger j=0; j<i; j++)
        {
            GLFloat c3=x[i]-x[j];
            c2=c2*c3;
            if (j==i-1) {
                for (NSUInteger k=mn; k>=1; k--) {
                    c[k*n+i] = c1*( ((GLFloat)k)*c[(k-1)*n+i-1] - c5*c[k*n+i-1] )/c2;
                }
                c[0*n+i] = -c1*c5*c[0*n+i-1]/c2;
            }
            
            for (NSUInteger k=mn; k>=1; k--) {
                c[k*n+j] = ( c4*c[k*n+j] - ((GLFloat)k)*c[(k-1)*n+j] )/c3;
            }
            c[0*n+j] = c4*c[0*n+j]/c3;
        }
        c1=c2;
    }
}

// This does not create fully generalized differentiation matrices, but creates matrices with a specific number of off-diagonal points.
// The interior points use central differencing, and will be of accuracy=2*bandwidth.
// The bandwidth must be at least floor(numDerivs/2) + 1
// End points (boundary conditions) will be of accuracy=bandwidth
// The bandwidth must be at least numDerivs of the boundary condition (e.g., Neuman boundary conditions require a bandwidth of 1).
+ (GLLinearTransform *) finiteDifferenceOperatorWithDerivatives: (NSUInteger) numDerivs leftBC: (GLBoundaryCondition) leftBC rightBC: (GLBoundaryCondition) rightBC bandwidth: (NSUInteger) bandwidth fromDimension: (GLDimension *) x forEquation: (GLEquation *) equation
{
	if (leftBC == kGLPeriodicBoundaryCondition || rightBC == kGLPeriodicBoundaryCondition) {
		[NSException raise:@"NotYetImplemented" format:@"Periodic boundary conditions are not yet implemented."];
	}
	
	if (bandwidth < ceil(((GLFloat)numDerivs)/2.)) {
		[NSException raise:@"InvalidBandwidth" format:@"The bandwidth must be at least floor(numDerivs/2) + 1."];
	}
	
	if (bandwidth < leftBC) {
		[NSException raise:@"InvalidBandwidth" format:@"The bandwidth must be at least the number of derivatives of the left boundary condition."];
	}
	
	if (bandwidth < rightBC) {
		[NSException raise:@"InvalidBandwidth" format:@"The bandwidth must be at least the number of derivatives of the right boundary condition."];
	}
	
	if (x.basisFunction != kGLDeltaBasis) {
		[NSException raise:@"InvalidBasis" format:@"Finite differencing requires a delta-basis."];
	}
	
	int n = 2*((int)bandwidth)+1;
	NSMutableData *buffer = [NSMutableData dataWithLength: n*(numDerivs+1)*sizeof(GLFloat)];
	
	// We can use central differencing as soon as the row >= bandwidth.
	// If the dimension is evenly sampled, we can use the same central difference weights throughout the interior.
	// For the moment we're implementing the *simplest* algorithm, not the most efficient.
	transformMatrix matrix = ^( NSUInteger *row, NSUInteger *col ) {
		GLFloat *xVal = (GLFloat *) x.data.bytes;
		GLFloat *c = buffer.mutableBytes;
		
		if (row[0] == 0 && abs((int)col[0]-(int)row[0]) <= bandwidth) { // leftBC
			weights( xVal[row[0]], &(xVal[row[0]]), leftBC, c, bandwidth+1);
			return (GLFloatComplex) c[leftBC*(bandwidth+1)+col[0]];
		} else if (row[0] == x.nPoints-1 && abs((int)col[0]-(int)row[0]) <= bandwidth) { // rightBC
			weights( xVal[row[0]], &(xVal[row[0]-bandwidth]), rightBC, c, bandwidth+1);
			return (GLFloatComplex) c[rightBC*(bandwidth+1) + (bandwidth+1)+(col[0]-x.nPoints)];
		} else if ( abs((int)col[0]-(int)row[0]) <= bandwidth) {
			NSUInteger a = row[0]<bandwidth?row[0]:bandwidth; // make sure we don't go below 0
			if (row[0]+bandwidth > x.nPoints-1) { // Fix issues when we get to the right side the matrix
				a += row[0]+bandwidth-x.nPoints+1;
			}
			weights( xVal[row[0]], &(xVal[row[0]-a]), numDerivs, c, n);
			return (GLFloatComplex) c[numDerivs*n + a+(col[0]-row[0])];
		} else {
			return (GLFloatComplex) 0.0;
		}
	};
	
	GLMatrixFormat matrixFormat = bandwidth == 1 ? kGLTridiagonalMatrixFormat : kGLDenseMatrixFormat;
	GLLinearTransform *diff = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[x] toDimensions: @[x] inFormat: @[@(matrixFormat)] forEquation: equation matrix: matrix];
	
	return diff;
}


//if ( row[0] == col[0] ) {
//	
//	printf("z=%6.2f\n\n", xVal[row[0]]);
//	
//	GLFloat *d = &(xVal[row[0]-a]);
//	for (NSUInteger i=0; i<n; i++) {
//		printf("%6.2f\t", d[i]);
//	}
//	printf("\n\n");
//	
//	for (NSUInteger i=0; i<numDerivs+1; i++) {
//		for (NSUInteger j=0; j<n; j++) {
//			printf("%6.2f\t", c[i*n+j]);
//		}
//		printf("\n");
//	}
//}

@end
