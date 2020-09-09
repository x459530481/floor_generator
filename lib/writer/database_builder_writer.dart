import 'package:code_builder/code_builder.dart';
import 'package:floor_generator/misc/annotations.dart';
import 'package:floor_generator/writer/writer.dart';

class DatabaseBuilderWriter extends Writer {
  final String _databaseName;
  final Database _database;

  DatabaseBuilderWriter(final String databaseName,final Database database;)
      : _databaseName = databaseName,
        _database = database;

  @nonNull
  @override
  Class write() {
    final databaseBuilderName = '_\$${_databaseName}Builder';

    final nameField = Field((builder) => builder
      ..name = 'name'
      ..type = refer('String')
      ..modifier = FieldModifier.final$);

    final migrationsField = Field((builder) => builder
      ..name = '_migrations'
      ..type = refer('List<Migration>')
      ..modifier = FieldModifier.final$
      ..assignment = const Code('[]'));

    final callbackField = Field((builder) => builder
      ..name = '_callback'
      ..type = refer('Callback'));

    final constructor = Constructor((builder) => builder
      ..requiredParameters.add(Parameter((builder) => builder
        ..toThis = true
        ..name = 'name')));

    final addMigrationsMethod = Method((builder) => builder
      ..name = 'addMigrations'
      ..returns = refer(databaseBuilderName)
      ..body = const Code('''
        _migrations.addAll(migrations);
        return this;
      ''')
      ..docs.add('/// Adds migrations to the builder.')
      ..requiredParameters.add(Parameter((builder) => builder
        ..name = 'migrations'
        ..type = refer('List<Migration>'))));

    final addCallbackMethod = Method((builder) => builder
      ..name = 'addCallback'
      ..returns = refer(databaseBuilderName)
      ..body = const Code('''
        _callback = callback;
        return this;
      ''')
      ..docs.add('/// Adds a database [Callback] to the builder.')
      ..requiredParameters.add(Parameter((builder) => builder
        ..name = 'callback'
        ..type = refer('Callback'))));

    final versionParameter = Parameter((builder) => builder
      ..name = 'version'
      ..toThis = refer('int'));
    final pswParameter = Parameter((builder) => builder
      ..name = 'psw'
      ..toThis = refer('String'));

    final createTableStatements =
    _generateCreateTableSqlStatements(database.entities)
        .map((statement) => "await database.execute('$statement');")
        .join('\n');
    final createIndexStatements = database.entities
        .map((entity) => entity.indices.map((index) => index.createQuery()))
        .expand((statements) => statements)
        .map((statement) => "await database.execute('$statement');")
        .join('\n');
    final createViewStatements = database.views
        .map((view) => view.getCreateViewStatement())
        .map((statement) => "await database.execute('''$statement''');")
        .join('\n');

    final buildMethod = Method((builder) => builder
      ..returns = refer('Future<$_databaseName>')
      ..name = 'build'
      ..modifier = MethodModifier.async
      ..docs.add('/// Creates the database and initializes it.')
      ..body = Code('''
        final path = name != null
          ? await sqfliteDatabaseFactory.getDatabasePath(name)
          : ':memory:';
        final database = _\$$_databaseName();
        
        database.database = await sqlcipher.openDatabase(path,
        version: version,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onOpen: (database) async {
          await _callback?.onOpen?.call(database);
        },
        onUpgrade: (database, startVersion, endVersion) async {
          await MigrationAdapter.runMigrations(
              database, startVersion, endVersion, _migrations);

          await _callback?.onUpgrade?.call(database, startVersion, endVersion);
        },
        onCreate: (database, version) async {
          $createTableStatements
          $createIndexStatements
          $createViewStatements
          await _callback?.onCreate?.call(database, version);
        },
        password: psw);
        return database;
      ''')
      ..requiredParameters.addAll([versionParameter,pswParameter]));

    return Class((builder) => builder
      ..name = databaseBuilderName
      ..fields.addAll([
        nameField,
        migrationsField,
        callbackField,
      ])
      ..constructors.add(constructor)
      ..methods.addAll([
        addMigrationsMethod,
        addCallbackMethod,
        buildMethod,
      ]));
  }
}
