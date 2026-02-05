import { vu } from 'k6/execution';

export default function () {
  console.log('vu object keys:', JSON.stringify(Object.keys(vu)));
  console.log('vu.id:', vu.id);
  console.log('vu.idInScenario:', vu.idInScenario);
  console.log('vu.idInInstance:', vu.idInInstance);
}
