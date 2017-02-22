//
//  SeameoCoreDataStack.h
//
//  Created by Ryan Migallos on 03/10/2016.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface CoreDataStack : NSObject

@property (nonatomic, readwrite) NSManagedObjectContext *mainContext;
@property (nonatomic, readwrite) NSManagedObjectContext *workerContext;

- (instancetype)initWithDataBase:(NSString *)fileName;
- (void)saveTreeContext:(NSManagedObjectContext *)context;
- (NSPredicate *)predicateForKeyPath:(NSString *)keypath andValue:(NSString *)value;
- (NSManagedObject *)entity:(NSString *)entity predicate:(NSPredicate *)predicate context:(NSManagedObjectContext *)context;
- (NSManagedObject *)getEntity:(NSString *)entity attribute:(NSString *)attribute
                     parameter:(NSString *)parameter context:(NSManagedObjectContext *)context;
- (BOOL)clearContentsForEntity:(NSString *)entity context:(NSManagedObjectContext *)context predicate:(NSPredicate *)predicate ;
@end
