Configuration.for 'app' do
  repositories [
    {
      name: '02JanDal/TestingTesting123',
      checks: [
        { check: :MaxOneCommit, data: {}},
        { check: :DescriptionSize, data: {minsize: 100}},
        { check: :GradleCheck, data: {tasks: ['setupForge']}}
      ]
    }
  ]
  access_token '9e6a545d521c1bf90d7cee753c6e199fcc8f46c5'
end
