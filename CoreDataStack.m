//
//  CoreDataStack.m
//
//  Created by Ryan Migallos on 03/10/2016.
//

#import "CoreDataStack.h"

@interface CoreDataStack()

@property (nonatomic, readwrite) NSManagedObjectContext *masterContext;
@property (nonatomic, readwrite) NSManagedObjectModel *model;
@property (nonatomic, readwrite) NSPersistentStore *store;
@property (nonatomic, readwrite) NSPersistentStoreCoordinator *coordinator;

@end

@implementation CoreDataStack

- (instancetype)initWithDataBase:(NSString *)fileName {
    
    if ( self = [super init] ) {
        
        // Managed Object Model
        self.model = [self coreDataModel:fileName];
        
        // Persistent Store Coordinator
        self.coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
        
        // CHECK COMPATIBILITY
        NSURL *databaseURL = [self databaseURLforFile:fileName];
        NSLog(@"database : %@", databaseURL.absoluteString);
        if ([self isCompatibleWithCoreDataMetadata:databaseURL] == NO) {
            self.store = nil;
        }
        
        // DATA FLUSHER
        // [WARNING: YOU ARE NOT ALLOWED TO USE THIS CONTEXT]
        // Core Data Stack for the Master Thread [MASTER] -> [PERSISTENTSTORE]
        self.masterContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [self.masterContext performBlockAndWait:^{
            [self.masterContext setPersistentStoreCoordinator:self.coordinator];
            [self.masterContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        }];
        
        // UI RELATED CONTEXT
        // Core Data Stack for the Main Thread [MAIN] -> [MASTER]
        self.mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [self.mainContext setParentContext:self.masterContext];
        [self.mainContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        
        // BACKGROUND CONTEXT
        // Core Data Stack for the Worker Thread [WORKER] -> [MAIN]
        self.workerContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [self.workerContext performBlockAndWait:^{
            [self.workerContext setParentContext:self.mainContext];
            [self.workerContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        }];
        
        // NOTE: THIS IS VERY IMPORTANT IN THE CREATION OF CORE DATA STACK
        // LOAD DATABASE FOR USE
        [self loadStore:databaseURL];
    }
    
    return self;
}

#pragma mark - Model Initialization

- (NSManagedObjectModel *)coreDataModel:(NSString *)name {
    
    NSBundle *appBundle = [NSBundle mainBundle];
    NSURL *modelFileURL = [appBundle URLForResource:name withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelFileURL];
    
    return model;
}

#pragma mark - PATHS

- (NSString *)documentsDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentationDirectory, NSUserDomainMask, YES) lastObject];
}

- (NSURL *)storeDirectory {
    
    NSString *filePath = [self documentsDirectory];
    NSURL *storesDirectory = [[NSURL fileURLWithPath:filePath] URLByAppendingPathComponent:@"db"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[storesDirectory path]]) {
        NSError *error = nil;
        if ([fileManager createDirectoryAtURL:storesDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Successfully created Stores directory");
            if (error) {
                NSLog(@"Failed to create Stores directory : %@", error);
            }
        }
    }
    return storesDirectory;
}

- (NSURL *)databaseURLforFile:(NSString *)name {
    
    // SQLite File Name
    NSString *sqliteFile = [NSString stringWithFormat:@"%@.sqlite", name];
    
    // SQLite Directory
    NSURL *fileURL = [self storeDirectory];
    
    // SQLite URL
    return [fileURL URLByAppendingPathComponent:sqliteFile];
}

- (BOOL)isCompatibleWithCoreDataMetadata:(NSURL *)storeUrl {
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *filePath = [NSString stringWithFormat:@"%@", storeUrl.path];
    
    if ([fm fileExistsAtPath:filePath]) {
        NSLog(@"checking model for compatibility...");
        NSError *error = nil;
        NSDictionary *options = [self databaseOptions];
        NSDictionary *dbInfo = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                                                          URL:storeUrl
                                                                                      options:options
                                                                                        error:&error];
        NSManagedObjectModel *model = self.coordinator.managedObjectModel;
        if ([model isConfiguration:nil compatibleWithStoreMetadata:dbInfo]) {
            NSLog(@"model is compatible...");
            return YES;
        } else {
            if ([fm removeItemAtPath:filePath error:NULL]) {
                NSLog(@"removed file : %@", filePath);
                NSLog(@"model is incompatible...");
                return NO;
            }//REMOVE THE STORE FILE
        }
    }
    
    NSLog(@"file does not exists..");
    return NO;
}

- (NSDictionary *)databaseOptions {
    
    //@{@"journal_mode" : @"WAL"}
    NSDictionary *sqliteConfig = @{@"journal_mode" : @"DELETE"};
    NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption  : @YES ,
                               NSInferMappingModelAutomaticallyOption        : @YES , //Light Weight Migration
                               NSSQLitePragmasOption                         : sqliteConfig };
    
    return options;
}

- (void)loadStore:(NSURL *)url {
    NSLog(@"Running - %s", __PRETTY_FUNCTION__);
    
    NSDictionary *options = [self databaseOptions];
    
    NSError *error = nil;
    self.store = [_coordinator addPersistentStoreWithType:NSSQLiteStoreType
                                            configuration:nil
                                                      URL:url
                                                  options:options
                                                    error:&error];
    if (self.store == nil) {
        //abort();
        NSLog(@"Failed to load store: %@", self.store);
    } else {
        NSLog(@"Successfully added store: %@", self.store);
    }
}

- (void)saveTreeContext:(NSManagedObjectContext *)context {
    
    NSLog(@"----> %s", __PRETTY_FUNCTION__);
    
    [context performBlockAndWait:^{
        if (context != nil) {
            NSError *error = nil;
            if ([context save:&error]) {
                if (context.parentContext != nil) {
                    NSManagedObjectContext *parent = context.parentContext;
                    [self saveTreeContext:parent];
                }
            }
        }
    }];
}

- (NSPredicate *)predicateForKeyPath:(NSString *)keypath andValue:(NSString *)value {
    
    // create left and right expression
    NSExpression *left = [NSExpression expressionForKeyPath:keypath];
    NSExpression *right = [NSExpression expressionForConstantValue:value];
    
    // predicate options
    NSComparisonPredicateOptions options = NSDiacriticInsensitivePredicateOption | NSCaseInsensitivePredicateOption;
    
    // create predicate
    NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression:left
                                                                rightExpression:right
                                                                       modifier:NSDirectPredicateModifier
                                                                           type:NSEqualToPredicateOperatorType
                                                                        options:options];
    return predicate;
}

- (NSManagedObject *)getEntity:(NSString *)entity attribute:(NSString *)attribute
                     parameter:(NSString *)parameter context:(NSManagedObjectContext *)context {
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entity];
    if (parameter) {
        
        // create predicate
        NSPredicate *predicate = [self predicateForKeyPath:attribute andValue:parameter];
        
        // set predicate
        [fetchRequest setPredicate:predicate];
    }
    
    NSError *error = nil;
    NSArray *items = [context executeFetchRequest:fetchRequest error:&error];
    if (error) {
        NSLog(@"error: %@", [error localizedDescription]);
    }
    
    if ([items count] > 0) {
        return [items lastObject];
    }
    
    return [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
}


- (NSManagedObject *)entity:(NSString *)entity predicate:(NSPredicate *)predicate context:(NSManagedObjectContext *)context {
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entity];
    if (predicate) {
        [fetchRequest setPredicate:predicate];
    }
    NSError *error = nil;
    NSArray *items = [context executeFetchRequest:fetchRequest error:&error];
    if (error) {
        NSLog(@"error: %@", [error localizedDescription]);
    }
    
    if ([items count] > 0) {
        return [items lastObject];
    }
    
    return nil;
}

- (BOOL)clearContentsForEntity:(NSString *)entity context:(NSManagedObjectContext *)context predicate:(NSPredicate *)predicate {
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entity];
    
    if (predicate) {
        [fetchRequest setPredicate:predicate];
    }
    
    NSArray *items = [context executeFetchRequest:fetchRequest error:nil];
    if ([items count] > 0) {
        for (NSManagedObject *lmo in items) {
            [context deleteObject:lmo];
        }
        [self saveTreeContext:context];
        
        return YES;
    }
    
    return NO;
}

@end
